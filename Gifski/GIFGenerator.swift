import Foundation
import CoreImage
import VideoToolbox
@preconcurrency import AVFoundation

actor GIFGenerator {
	private var gifski: Gifski?
	private(set) var sizeMultiplierForEstimation = 1.0

	static func run(
		_ conversion: Conversion,
		isEstimation: Bool = false,
		onProgress: @escaping (Double) -> Void
	) async throws -> Data {
		let converter = Self()

		return try await converter.run(
			conversion,
			isEstimation: isEstimation,
			onProgress: onProgress
		)
	}

	/**
	Converts a single frame to GIF data.
	*/
	static func convertOneFrame(
		frame: CGImage,
		dimensions: (width: Int, height: Int)?,
		quality: Double,
		fast: Bool = false
	) async throws -> Data {
		let gifski = try Gifski(
			dimensions: dimensions,
			quality: quality,
			loop: .never,
			fast: fast
		)

		try gifski.addFrame(frame, presentationTimestamp: 0.0)

		return try gifski.finish()
	}

	deinit {
		print("GIFGenerator DEINIT")
	}

	// TODO: Make private.
	/**
	Converts a movie to GIF.
	*/
	func run(
		_ conversion: Conversion,
		isEstimation: Bool = false,
		onProgress: @escaping (Double) -> Void
	) async throws -> Data {
		gifski = try Gifski(
			dimensions: conversion.dimensions,
			quality: conversion.quality.clamped(to: 0.1...1),
			loop: conversion.loop
		)

		defer {
			// Ensure Gifski finishes no matter what.
			gifski = nil
		}

		let result = try await generateData(
			for: conversion,
			isEstimation: isEstimation,
			onProgress: onProgress
		)

		try Task.checkCancellation()

		return result
	}

	/**
	Generates GIF data for the provided conversion.

	- Parameters:
		- conversion: The source information of the conversion.
		- isEstimation: Whether the frame is part of a size estimation job.
		- onProgress: Closure called when conversion progress advances.
	*/
	private func generateData(
		for conversion: Conversion,
		isEstimation: Bool,
		onProgress: @escaping (Double) -> Void
	) async throws -> Data {
		let (reader, output, targetFrameTimes, frameRate) = try await makeFrameReader(for: conversion)
		var frameTimes = targetFrameTimes

		// TODO: The whole estimation thing should be split out into a separate method and the things that are shared should also be split out.
		if isEstimation {
			let originalCount = frameTimes.count

			if originalCount > 25 {
				// Take 25 consecutive middle frames. AVAssetReader reads sequentially, so we cannot sample from spread-out positions like the old AVAssetImageGenerator path. Consecutive sampling can skew estimates for videos with non-uniform motion, but it is accurate enough in practice.
				let sampleCount = 25
				let startIndex = (originalCount - sampleCount) / 2
				frameTimes = Array(frameTimes[startIndex..<(startIndex + sampleCount)])

				if
					let firstFrameTime = frameTimes.first,
					let lastFrameTime = frameTimes.last,
					lastFrameTime > firstFrameTime
				{
					let endTime = CMTimeAdd(
						lastFrameTime,
						CMTime(seconds: 1 / frameRate, preferredTimescale: lastFrameTime.timescale)
					)
					reader.timeRange = CMTimeRange(start: firstFrameTime, end: min(endTime, reader.timeRange.end))
				}
			}

			sizeMultiplierForEstimation = frameTimes.isEmpty ? 1.0 : Double(originalCount) / Double(frameTimes.count)
		}

		let totalFrameCount = totalFrameCount(for: conversion, sourceFrameCount: frameTimes.count)

		var completedFrameCount = 0
		gifski?.onProgress = {
			let progress = Double(completedFrameCount.increment()) / Double(totalFrameCount)
			onProgress(progress.clamped(to: 0...1)) // TODO: For some reason, when we use `bounce`, `totalFrameCount` can be 1 less than `completedFrameCount` on completion.
		}

		// TODO: Use `Duration`.
		let startTime = frameTimes.first?.seconds ?? 0
		let loopDelayOffset = conversion.loop.isLooping ? conversion.loopDelay : 0

		print("Total frame count:", totalFrameCount)

		guard let gifski else {
			throw CancellationError()
		}

		try addFrames(
			to: gifski,
			reader: reader,
			output: output,
			frameTimes: frameTimes,
			conversion: conversion,
			totalFrameCount: totalFrameCount,
			frameRate: frameRate,
			startTime: startTime,
			loopDelayOffset: loopDelayOffset
		)

		return try gifski.finish()
	}

	// We intentionally do not use `withTaskCancellationHandler` to call `reader.cancelReading()` here because `AVAssetReader` is not thread-safe and concurrent `cancelReading()` + `copyNextSampleBuffer()` causes EXC_BAD_ACCESS crashes inside MediaToolbox. Instead, we rely on cooperative cancellation: `readFrames` checks `Task.checkCancellation()` each iteration and the `defer` block calls `cancelReading()` safely from the same thread.
	private func addFrames(
		to gifski: Gifski,
		reader: AVAssetReader,
		output: AVAssetReaderVideoCompositionOutput,
		frameTimes: [CMTime],
		conversion: Conversion,
		totalFrameCount: Int,
		frameRate: Double,
		startTime: Double,
		loopDelayOffset: Double
	) throws {
		try readFrames(
			to: gifski,
			reader: reader,
			output: output,
			frameTimes: frameTimes,
			conversion: conversion,
			totalFrameCount: totalFrameCount,
			frameRate: frameRate,
			startTime: startTime,
			loopDelayOffset: loopDelayOffset
		)
	}

	/**
	Creates a sequential frame reader for the provided conversion.

	- Parameters:
		- conversion: The conversion source of the reader.
	- Returns: An `AVAssetReader`, its video output, the target frame times, and the target GIF frame rate.
	*/
	private func makeFrameReader(for conversion: Conversion) async throws -> (reader: AVAssetReader, output: AVAssetReaderVideoCompositionOutput, targetFrameTimes: [CMTime], frameRate: Double) {
		let asset = conversion.asset
//
//		record(
//			jobKey: jobKey,
//			key: "Is readable?",
//			value: asset.isReadable
//		)
//		record(
//			jobKey: jobKey,
//			key: "First video track",
//			value: asset.firstVideoTrack
//		)
//		record(
//			jobKey: jobKey,
//			key: "First video track time range",
//			value: asset.firstVideoTrack?.timeRange
//		)
//		record(
//			jobKey: jobKey,
//			key: "Duration",
//			value: asset.duration.seconds
//		)
//		record(
//			jobKey: jobKey,
//			key: "AVAsset debug info",
//			value: asset.debugInfo
//		)

		// Parallelize independent loads.
		async let isReadableCheck = asset.load(.isReadable)
		async let frameRateCheck = asset.frameRate
		async let firstVideoTrackCheck = asset.firstVideoTrack

		guard
			try await isReadableCheck,
			let assetFrameRate = try await frameRateCheck,
			let firstVideoTrack = try await firstVideoTrackCheck
		else {
			// This can happen if the user selects a file, and then the file becomes
			// unavailable or deleted before the "Convert" button is clicked.
			throw Error.unreadableFile
		}

		// Use the first video track range because the total asset duration can be longer than the video track. Reading past the video track can fail or stall (#119).
		let (timeRange, timescale) = try await firstVideoTrack.load(.timeRange, .naturalTimeScale)
		guard let videoTrackRange = timeRange.range else {
			throw Error.unreadableFile
		}
//
//		record(
//			jobKey: jobKey,
//			key: "AVAsset debug info2",
//			value: asset.debugInfo
//		)

		// Explicit frame rate is authoritative because speed-adjusted compositions can legitimately need more frames per second than the source track's nominal FPS.
		let frameRate = (conversion.frameRate.map(Double.init) ?? assetFrameRate).clamped(to: 0.1...Constants.allowedFrameRate.upperBound)

		print("Video FPS:", frameRate)

		// TODO: Instead of calculating what part of the video to get, we could just trim the actual `AVAssetTrack`.
		let videoRange = conversion.timeRange?.clampingBounds(to: videoTrackRange) ?? videoTrackRange
		let startTime = videoRange.lowerBound
		let duration = videoRange.length
		let frameCount = Int(duration * frameRate)
		let frameStep = 1 / frameRate

		print("Video frame count:", frameCount)

		guard frameCount >= 2 else {
			throw Error.notEnoughFrames(frameCount)
		}

		var targetFrameTimes: [CMTime] = (0..<frameCount).map { index in
			let presentationTimestamp = startTime + (frameStep * Double(index))
			return CMTime(
				seconds: presentationTimestamp,
				preferredTimescale: timescale
			)
		}

		// We don't do this when "bounce" is enabled as the bounce calculations are not able to handle this.
		if !conversion.bounce {
			// Ensure we include the last frame. For example, the above might have calculated `[..., 6.25, 6.3]`, but the duration is `6.3647`, so we might miss the last frame if it appears for a short time.
			targetFrameTimes.append(CMTime(seconds: startTime + duration, preferredTimescale: timescale))
		}
//
//		record(
//			jobKey: jobKey,
//			key: "frameRate",
//			value: frameRate
//		)
//		record(
//			jobKey: jobKey,
//			key: "videoRange",
//			value: videoRange
//		)
//		record(
//			jobKey: jobKey,
//			key: "frameCount",
//			value: frameCount
//		)
//		record(
//			jobKey: jobKey,
//			key: "targetFrameTimes",
//			value: targetFrameTimes.map(\.seconds)
//		)

		let frameDuration = CMTime(seconds: frameStep, preferredTimescale: timescale)
		let readerEndTime = min(videoRange.upperBound + frameStep, videoTrackRange.upperBound)
		let reader = try AVAssetReader(asset: asset)
		reader.timeRange = (videoRange.lowerBound...readerEndTime).cmTimeRange

		// Read frames sequentially through a video composition so AVFoundation applies scale, crop, and orientation in one decode pass.
		let output = try await makeFrameReaderOutput(
			conversion: conversion,
			videoTrack: firstVideoTrack,
			frameDuration: frameDuration
		)

		guard reader.canAdd(output) else {
			throw Error.unreadableFile
		}

		reader.add(output)

		return (reader, output, targetFrameTimes, frameRate)
	}

	private func makeFrameReaderOutput(
		conversion: Conversion,
		videoTrack: AVAssetTrack,
		frameDuration: CMTime
	) async throws -> AVAssetReaderVideoCompositionOutput {
		let output = AVAssetReaderVideoCompositionOutput(
			videoTracks: [videoTrack],
			videoSettings: CVPixelBuffer.bgra32Attributes
		)
		output.alwaysCopiesSampleData = false
		output.videoComposition = try await conversion.alphaPreservingVideoComposition(
			for: videoTrack,
			frameDuration: frameDuration
		)

		return output
	}

	private func readFrames(
		to gifski: Gifski,
		reader: AVAssetReader,
		output: AVAssetReaderVideoCompositionOutput,
		frameTimes: [CMTime],
		conversion: Conversion,
		totalFrameCount: Int,
		frameRate: Double,
		startTime: Double,
		loopDelayOffset: Double
	) throws {
		guard reader.startReading() else {
			throw Error.generateFrameFailed(reader.error ?? Error.unreadableFile)
		}
		defer {
			if reader.status == .reading {
				reader.cancelReading()
			}
		}

		guard let firstSampleBuffer = output.copyNextSampleBuffer() else {
			try throwIfReaderFailedOrWasCancelled(reader)
			throw Error.generateFrameFailed(reader.error ?? Error.unreadableFile)
		}

		var frameNumber = 0
		var previousSampleBuffer = firstSampleBuffer

		while frameNumber < frameTimes.count {
			try Task.checkCancellation()

			guard let sampleBuffer = output.copyNextSampleBuffer() else {
				break
			}

			// `outputPresentationTimeStamp` is in the composed output timeline, which is what `frameTimes` uses after trimming, speed changes, and video composition transforms.
			let sampleTime = sampleBuffer.outputPresentationTimeStamp

			if sampleTime > frameTimes[frameNumber] {
				// `AVAssetReader` emits composed frames, while `frameTimes` are the GIF output times. Use the previous decoded sample for every target time before the current output frame.
				let image = try cgImage(from: previousSampleBuffer)

				while
					frameNumber < frameTimes.count,
					sampleTime > frameTimes[frameNumber]
				{
					try addFrame(
						to: gifski,
						image: image,
						frameNumber: frameNumber,
						presentationTimestamp: max(0, frameTimes[frameNumber].seconds - startTime) + loopDelayOffset,
						conversion: conversion,
						totalFrameCount: totalFrameCount,
						frameRate: frameRate,
						loopDelayOffset: loopDelayOffset
					)
					frameNumber += 1
				}
			}

			previousSampleBuffer = sampleBuffer
		}

		if frameNumber < frameTimes.count {
			try throwIfReaderFailedOrWasCancelled(reader)

			// The requested GIF can include the exact end time, which may be after the last decoded sample. Reuse the final source frame for any remaining target times.
			let image = try cgImage(from: previousSampleBuffer)

			while frameNumber < frameTimes.count {
				try addFrame(
					to: gifski,
					image: image,
					frameNumber: frameNumber,
					presentationTimestamp: max(0, frameTimes[frameNumber].seconds - startTime) + loopDelayOffset,
					conversion: conversion,
					totalFrameCount: totalFrameCount,
					frameRate: frameRate,
					loopDelayOffset: loopDelayOffset
				)
				frameNumber += 1
			}
		}

		try throwIfReaderFailedOrWasCancelled(reader)
	}

	/**
	Throws if the reader failed or was cancelled.
	*/
	private func throwIfReaderFailedOrWasCancelled(_ reader: AVAssetReader) throws {
		switch reader.status {
		case .completed, .reading:
			break
		case .failed:
			throw Error.generateFrameFailed(reader.error ?? Error.unreadableFile)
		case .cancelled:
			throw CancellationError()
		case .unknown:
			throw Error.unreadableFile
		@unknown default:
			throw Error.unreadableFile
		}
	}

	private func cgImage(from sampleBuffer: CMSampleBuffer) throws(Error) -> CGImage {
		guard let pixelBuffer = sampleBuffer.imageBuffer else {
			throw .missingPixelBuffer
		}

		var cgImage: CGImage?
		let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

		guard
			status == noErr,
			let cgImage
		else {
			throw .couldNotCreateImageFromFrame
		}

		return cgImage
	}

	private func addFrame(
		to gifski: Gifski,
		image: CGImage,
		frameNumber: Int,
		presentationTimestamp: Double,
		conversion: Conversion,
		totalFrameCount: Int,
		frameRate: Double,
		loopDelayOffset: Double
	) throws {
		do {
			try gifski.addFrame(
				image,
				frameNumber: frameNumber,
				presentationTimestamp: presentationTimestamp
			)
		} catch {
			throw Error.addFrameFailed(error)
		}

		guard conversion.bounce else {
			return
		}

		/*
		Inserts the frame again at the reverse index of the natural order.

		For example, if this frame is at index 2 of 5 in its natural order:

		```
			  ↓
		0, 1, 2, 3, 4
		```

		Then the frame should be inserted at 6 of 9 in the reverse order:

		```
						  ↓
		0, 1, 2, 3, 4, 3, 2, 1, 0
		```
		*/
		let reverseFrameNumber = totalFrameCount - frameNumber - 1

		// Prevent duplicate frame with the same frame number causing an unwanted frame at the end of the GIF.
		guard frameNumber != reverseFrameNumber else {
			return
		}

		do {
			try gifski.addFrame(
				image,
				frameNumber: reverseFrameNumber,
				presentationTimestamp: max(0, TimeInterval(reverseFrameNumber) / frameRate) + loopDelayOffset
			)
		} catch {
			throw Error.addFrameFailed(error)
		}
	}

	private func totalFrameCount(for conversion: Conversion, sourceFrameCount: Int) -> Int {
		/*
		Bouncing doubles the frame count except for the frame at the apex (middle) of the bounce.

		For example, a sequence of 5 frames becomes a sequence of 9 frames when bounced:

		```
		0, 1, 2, 3, 4
		            ↓
		0, 1, 2, 3, 4, 3, 2, 1, 0
		```
		*/
		conversion.bounce ? (sourceFrameCount * 2 - 1) : sourceFrameCount
	}
}


extension GIFGenerator {
	/**
	- Parameter frameRate: Clamped to `Constants.allowedFrameRate` (3...50). Uses the frame rate of `input` if not specified.
	- Parameter loopGif: Whether output should loop infinitely or not.
	- Parameter bounce: Whether output should bounce or not.
	*/
	struct Conversion: ReflectiveHashable { // TODO
		let asset: AVAsset
		let sourceURL: URL
		var timeRange: ClosedRange<Double>?
		var quality = 1.0
		var dimensions: (width: Int, height: Int)?
		var frameRate: Int?
		var loop: Gifski.Loop
		var bounce: Bool
		var loopDelay = 0.0
		var crop: CropRect?
		var trackPreferredTransform: CGAffineTransform?
	}
}

extension GIFGenerator.Conversion {
	var gifDuration: Duration {
		get async throws {
			// TODO: Make this lazy so it's only used for fallback.
			let fallbackRange = try await asset.firstVideoTrack?.load(.timeRange)
			return gifDuration(assetTimeRange: fallbackRange)
		}
	}

	func gifDuration(assetTimeRange fallbackRange: CMTimeRange?, withBounce: Bool = true) -> Duration {
		guard let duration = (timeRange ?? fallbackRange?.range)?.length else {
			return .zero
		}

		// TODO: Do this when Swift supports async in `??`.
		//				guard let duration = (timeRange ?? asset.firstVideoTrack?.timeRange.range)?.length else {
		//					return .zero
		//				}
		return .seconds(withBounce && bounce ? (duration * 2) : duration)
	}

	var videoWithoutBounceDuration: Duration {
		get async throws {
			.seconds(try await gifDuration.toTimeInterval / (bounce ? 2 : 1))
		}
	}

	/**
	- Returns: The current scale of the `dimensions` compared to the dimensions of the video track.
	*/
	var scale: CGSize {
		get async throws {
			guard let videoTrack = try await asset.firstVideoTrack else {
				return .one
			}

			return try await scale(for: videoTrack)
		}
	}

	/**
	Returns the current scale of the explicit output dimensions compared to the provided video track.
	*/
	func scale(for videoTrack: AVAssetTrack) async throws -> CGSize {
		guard let trackDimensions = try await videoTrack.dimensions else {
			return .one
		}
		guard trackDimensions > 0 else {
			throw Error.invalidDimensions
		}
		guard let dimensionsAsCGSize else {
			return .one
		}

		let scale = uncroppedRenderSize(forOutputSize: dimensionsAsCGSize) / trackDimensions
		guard scale > 0 else {
			throw Error.invalidScale
		}
		return scale
	}

	var dimensionsAsCGSize: CGSize? {
		dimensions.map {
			.init(width: Double($0.0), height: Double($0.1))
		}
	}

	/**
	The full render size, accounting for crop (scaled up so that the crop region yields the requested output size).
	*/
	var renderSize: CGSize {
		get async throws {
			guard let videoTrack = try await asset.firstVideoTrack else {
				throw Error.invalidDimensions
			}

			return try await renderSize(for: videoTrack)
		}
	}

	/**
	Returns the render size for the provided track, using explicit conversion dimensions when set.
	*/
	func renderSize(for videoTrack: AVAssetTrack) async throws -> CGSize {
		if let dimensionsAsCGSize {
			return uncroppedRenderSize(forOutputSize: dimensionsAsCGSize)
		}

		guard let trackSize = try await videoTrack.dimensions else {
			throw Error.invalidDimensions
		}

		return trackSize
	}

	/**
	Returns the full render size before crop for the requested final output size.
	*/
	func uncroppedRenderSize(forOutputSize outputSize: CGSize) -> CGSize {
		guard
			let crop,
			crop.width > 0,
			crop.height > 0
		else {
			return outputSize
		}

		return CGSize(
			width: outputSize.width / crop.width,
			height: outputSize.height / crop.height
		)
	}

	/**
	The crop to apply, falling back to the full frame when none is set.
	*/
	var resolvedCrop: CropRect {
		crop ?? .initial
	}

	/**
	- Returns: Crop rect in pixels, if there is no crop rect then it returns the full render size.
	*/
	var cropRectInPixels: CGRect {
		get async throws {
			resolvedCrop.unnormalize(forDimensions: try await renderSize)
		}
	}

	/**
	The crop rect applied to the natural (unrotated) size of the video track.

	The crop rect from the UI is defined in the preferred/rotated space (how the user sees the video). To apply it to `naturalSize`, we need to transform it from rotated space to natural space.
	*/
	var cropRectInNaturalSpace: CGRect {
		get async throws {
			guard let videoTrack = try await asset.firstVideoTrack else {
				return .zero
			}

			let (naturalSize, preferredTransform) = try await videoTrack.load(.naturalSize, .preferredTransform)
			return cropRectInNaturalSpace(naturalSize: naturalSize, preferredTransform: preferredTransform)
		}
	}

	/**
	Returns the crop rect transformed from preferred/rotated space into the provided natural video space.
	*/
	func cropRectInNaturalSpace(
		naturalSize: CGSize,
		preferredTransform: CGAffineTransform
	) -> CGRect {
		let rotatedDimensions = naturalSize.applyingAbsolute(preferredTransform)

		let cropRectInRotatedSpace = resolvedCrop.unnormalize(forDimensions: rotatedDimensions)

		return cropRectInRotatedSpace.applying(preferredTransform.inverted())
	}

	/**
	Loads `videoTrack`'s natural size together with the effective preferred transform — the `trackPreferredTransform` override when set, otherwise the track's own.
	*/
	func geometry(for videoTrack: AVAssetTrack) async throws -> (naturalSize: CGSize, preferredTransform: CGAffineTransform) {
		let (naturalSize, loadedPreferredTransform) = try await videoTrack.load(.naturalSize, .preferredTransform)
		return (naturalSize, trackPreferredTransform ?? loadedPreferredTransform)
	}

	/**
	Creates an `AVVideoComposition` that crops, scales, and orients the source to this conversion's output settings while preserving the source's alpha channel. `geometryTrack` lets export apply the source track's natural size and orientation while reading frames from an `AVMutableCompositionTrack`. `preservesSourceFrameTiming` renders frames at the source frame times instead of at a fixed `frameDuration` cadence, which keeps variable-frame-rate timing intact.

	The built-in `AVVideoComposition` compositor (used by `videoComposition(for:…)`) flattens the alpha channel to opaque, which loses transparency from alpha-capable sources like ProRes 4444. The Core Image based `AlphaPreservingCompositor` preserves it.
	*/
	func alphaPreservingVideoComposition(
		for videoTrack: AVAssetTrack,
		usingGeometryOf geometryTrack: AVAssetTrack? = nil,
		frameDuration: CMTime,
		preservesSourceFrameTiming: Bool = false
	) async throws -> AVVideoComposition {
		let (naturalSize, preferredTransform) = try await geometry(for: geometryTrack ?? videoTrack)
		// Pad the instruction's range by one frame so a final frame landing on the track boundary is still covered.
		let loadedTimeRange = try await videoTrack.load(.timeRange)
		let timeRange = CMTimeRange(start: loadedTimeRange.start, duration: loadedTimeRange.duration + frameDuration)

		let displaySize = naturalSize.applyingAbsolute(preferredTransform)

		let crop = resolvedCrop
		let outputSize = dimensionsAsCGSize ?? crop.unnormalize(forDimensions: displaySize).size

		let instruction = AlphaPreservingCompositor.Instruction(
			timeRange: timeRange,
			trackID: videoTrack.trackID,
			preferredTransform: preferredTransform,
			crop: crop,
			outputSize: outputSize
		)

		let configuration = AVVideoComposition.Configuration(
			customVideoCompositorClass: AlphaPreservingCompositor.self,
			frameDuration: frameDuration,
			instructions: [instruction],
			renderSize: outputSize,
			sourceTrackIDForFrameTiming: preservesSourceFrameTiming ? videoTrack.trackID : kCMPersistentTrackID_Invalid
		)

		return AVVideoComposition(configuration: configuration)
	}

	/**
	Creates an `AVVideoComposition` that scales, translates, and crops `videoTrack` using this conversion's output settings. `geometryTrack` lets export apply the source track's natural size and orientation while rendering an `AVMutableCompositionTrack`. `preservesSourceFrameTiming` renders frames at the source frame times instead of at a fixed `frameDuration` cadence, which keeps variable-frame-rate timing intact.
	*/
	func videoComposition(
		for videoTrack: AVAssetTrack,
		usingGeometryOf geometryTrack: AVAssetTrack? = nil,
		timeRange: CMTimeRange,
		frameDuration: CMTime,
		preservesSourceFrameTiming: Bool = false
	) async throws -> AVVideoComposition {
		let geometryTrack = geometryTrack ?? videoTrack
		let outputRenderSize = resolvedCrop.unnormalize(forDimensions: try await renderSize(for: geometryTrack)).size
		// Layer instructions operate in natural space (unrotated). The crop rect from UI is in preferred space, so transform it back to natural space before applying it.
		let (naturalSize, preferredTransform) = try await geometry(for: geometryTrack)
		let cropRect = cropRectInNaturalSpace(naturalSize: naturalSize, preferredTransform: preferredTransform)
		let scaleTransform = CGAffineTransform(scaledBy: try await scale(for: geometryTrack))
		// Crop is applied before the layer transform, so translate using the crop rect after scale and preferred orientation have moved it into render space.
		let scaledCropRect = cropRect.applying(scaleTransform)
		let cropRectAfterPreferred = scaledCropRect.applying(preferredTransform)

		// Place the crop rect in the top left corner.
		let translateTransform = CGAffineTransform(translationX: -cropRectAfterPreferred.minX, y: -cropRectAfterPreferred.minY)

		var layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: videoTrack)
		layerConfig.setCropRectangle(cropRect, at: .zero)
		layerConfig.setTransform(scaleTransform.concatenating(preferredTransform).concatenating(translateTransform), at: .zero)

		let instructionConfig = AVVideoCompositionInstruction.Configuration(
			layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layerConfig)],
			timeRange: timeRange
		)
		let configuration = AVVideoComposition.Configuration(
			frameDuration: frameDuration,
			instructions: [AVVideoCompositionInstruction(configuration: instructionConfig)],
			renderSize: outputRenderSize,
			sourceTrackIDForFrameTiming: preservesSourceFrameTiming ? videoTrack.trackID : kCMPersistentTrackID_Invalid
		)

		return AVVideoComposition(configuration: configuration)
	}

	/**
	- Returns: The time range used to export the modified video (i.e. not the `.gif` export).
	*/
	var exportModifiedVideoTimeRange: CMTimeRange {
		get async throws {
			if let timeRange {
				return timeRange.cmTimeRange
			}
			return (0...(try await videoWithoutBounceDuration.toTimeInterval)).cmTimeRange
		}
	}

	var firstVideoTrack: AVAssetTrack {
		get async throws {
			guard let videoTrack = try await asset.firstVideoTrack else {
				throw Error.noVideoTrack
			}
			return videoTrack
		}
	}

	enum Error: Swift.Error {
		case invalidDimensions
		case invalidScale
		case noVideoTrack
	}
}

extension GIFGenerator {
	enum Error: LocalizedError {
		case invalidSettings
		case unreadableFile
		case notEnoughFrames(Int)
		case missingPixelBuffer
		case couldNotCreateImageFromFrame
		case generateFrameFailed(Swift.Error)
		case addFrameFailed(Swift.Error)
		case writeFailed(Swift.Error)
		case cancelled

		var errorDescription: String? {
			switch self {
			case .invalidSettings:
				"Invalid settings."
			case .unreadableFile:
				"The selected file is no longer readable."
			case .notEnoughFrames(let frameCount):
				"An animated GIF requires a minimum of 2 frames. Your video contains \(frameCount) frame\(frameCount == 1 ? "" : "s")."
			case .missingPixelBuffer:
				"The video frame did not contain a pixel buffer."
			case .couldNotCreateImageFromFrame:
				"Could not create an image from the video frame."
			case .generateFrameFailed(let error):
				"Failed to generate frame: \(error.localizedDescription)"
			case .addFrameFailed(let error):
				"Failed to add frame, with underlying error: \(error.localizedDescription)"
			case .writeFailed(let error):
				"Failed to write, with underlying error: \(error.localizedDescription)"
			case .cancelled:
				"The conversion was cancelled."
			}
		}
	}
}

extension GIFGenerator {
	static func runProgressable(_ conversion: GIFGenerator.Conversion) -> ProgressableTask<Double, Data> {
		ProgressableTask { progressContinuation in
			try await run(conversion) {
				progressContinuation.yield($0)
			}
		}
	}
}

/**
A video compositor that crops, scales, and orients the source while preserving its alpha channel.

The built-in `AVVideoComposition` compositor flattens the alpha channel to opaque, which loses transparency from alpha-capable sources like ProRes 4444. Core Image preserves it.
*/
private final class AlphaPreservingCompositor: NSObject, AVVideoCompositing {
	/**
	The per-conversion geometry, passed to the compositor through the composition instruction.
	*/
	final class Instruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
		let timeRange: CMTimeRange
		let enablePostProcessing = false
		let containsTweening = false
		// swiftlint:disable:next discouraged_optional_collection
		let requiredSourceTrackIDs: [NSValue]?
		let passthroughTrackID = kCMPersistentTrackID_Invalid

		let preferredTransform: CGAffineTransform
		let crop: CropRect
		let outputSize: CGSize

		init(
			timeRange: CMTimeRange,
			trackID: CMPersistentTrackID,
			preferredTransform: CGAffineTransform,
			crop: CropRect,
			outputSize: CGSize
		) {
			self.timeRange = timeRange
			self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
			self.preferredTransform = preferredTransform
			self.crop = crop
			self.outputSize = outputSize
		}
	}

	enum Error: Swift.Error {
		case missingSourceFrame
	}

	// swiftlint:disable:next discouraged_optional_collection
	let sourcePixelBufferAttributes: [String: any Sendable]? = CVPixelBuffer.bgra32Attributes

	let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = CVPixelBuffer.bgra32Attributes

	private let context = CIContext()

	func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

	func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
		guard
			let instruction = request.videoCompositionInstruction as? Instruction,
			let trackID = request.sourceTrackIDs.first?.int32Value,
			let sourceBuffer = request.sourceFrame(byTrackID: trackID),
			let outputBuffer = request.renderContext.newPixelBuffer()
		else {
			request.finish(with: Error.missingSourceFrame)
			return
		}

		// `CIImage` wraps the source buffer in natural (unrotated) space with a bottom-left origin, while `preferredTransform` is defined in AVFoundation's top-left space. Flip to top-left, apply the rotation, then flip back, leaving the image in the preferred display orientation so the crop coordinates (also display space) apply directly.
		var image = CIImage(cvPixelBuffer: sourceBuffer)
		let flip = CGAffineTransform(translationX: 0, y: image.extent.height).scaledBy(x: 1, y: -1)
		image = image.transformed(by: flip.concatenating(instruction.preferredTransform).concatenating(flip))
		// Rotations can leave the extent off-origin, so move it back to (0, 0) before cropping.
		image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))

		let cropRect = instruction.crop.unnormalize(forDimensions: image.extent.size)
		// Core Image uses a bottom-left origin, so flip the crop rect's Y within the image height.
		let flippedCropRect = CGRect(
			x: cropRect.minX,
			y: image.extent.height - cropRect.maxY,
			width: cropRect.width,
			height: cropRect.height
		)
		image = image
			.cropped(to: flippedCropRect)
			.transformed(by: CGAffineTransform(translationX: -flippedCropRect.minX, y: -flippedCropRect.minY))

		// Scale the cropped region to the output size so downstream work matches the final dimensions instead of the full source resolution.
		image = image.transformed(by: CGAffineTransform(
			scaleX: instruction.outputSize.width / cropRect.width,
			y: instruction.outputSize.height / cropRect.height
		))

		context.render(image, to: outputBuffer)
		request.finish(withComposedVideoFrame: outputBuffer)
	}
}
