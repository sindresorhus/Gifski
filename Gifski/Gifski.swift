import Foundation
import AVFoundation
import FirebaseCrashlytics

private var conversionCount = 0

final class Gifski {
	enum Error: LocalizedError {
		case invalidSettings
		case unreadableFile
		case notEnoughFrames(Int)
		case generateFrameFailed(Swift.Error)
		case addFrameFailed(Swift.Error)
		case writeFailed(Swift.Error)
		case cancelled

		var errorDescription: String? {
			switch self {
			case .invalidSettings:
				return "Invalid settings."
			case .unreadableFile:
				return "The selected file is no longer readable."
			case .notEnoughFrames(let frameCount):
				return "An animated GIF requires a minimum of 2 frames. Your video contains \(frameCount) frame\(frameCount == 1 ? "" : "s")."
			case .generateFrameFailed(let error):
				return "Failed to generate frame: \(error.localizedDescription)"
			case .addFrameFailed(let error):
				return "Failed to add frame, with underlying error: \(error.localizedDescription)"
			case .writeFailed(let error):
				return "Failed to write, with underlying error: \(error.localizedDescription)"
			case .cancelled:
				return "The conversion was cancelled."
			}
		}
	}

	/**
	- Parameter frameRate: Clamped to `5...30`. Uses the frame rate of `input` if not specified.
	- Parameter loopGif: Whether output should loop infinitely or not.
	*/
	struct Conversion {
		let video: URL
		var timeRange: ClosedRange<Double>?
		var quality: Double = 1
		var dimensions: CGSize?
		var frameRate: Int?
		var loopCount: Int?
	}

	private var gifData = Data()
	private var progress: Progress!
	private var gifski: GifskiWrapper?

	private(set) var sizeMultiplierForEstimation = 1.0

	deinit {
		cancel()
	}

	/**
	Converts a movie to GIF.

	- Parameter completionHandler: Guaranteed to be called on the main thread
	*/
	func run(
		_ conversion: Conversion,
		isEstimation: Bool,
		completionHandler: @escaping (Result<Data, Error>) -> Void
	) {
		// For debugging.
		conversionCount += 1
		let jobKey = "Conversion \(conversionCount)"

		progress = Progress(parent: .current())

		let completionHandlerOnce = Once().wrap { [weak self] (_ result: Result<Data, Error>) -> Void in
			// Ensure libgifski finishes no matter what.
			try? self?.gifski?.finish()
			self?.gifski?.release()

			DispatchQueue.main.async {
				guard
					let self = self,
					!self.progress.isCancelled
				else {
					completionHandler(.failure(.cancelled))
					return
				}

				completionHandler(result)
			}
		}

		let settings = GifskiSettings(
			width: UInt32(conversion.dimensions?.width ?? 0),
			height: UInt32(conversion.dimensions?.height ?? 0),
			quality: UInt8(conversion.quality * 100),
			fast: false,
			repeat: Int16(conversion.loopCount ?? 0)
		)

		self.gifski = GifskiWrapper(settings: settings)

		guard let gifski = gifski else {
			completionHandlerOnce(.failure(.invalidSettings))
			return
		}

		gifski.setProgressCallback { [weak self] in
			guard let self = self else {
				return 1
			}

			self.progress.completedUnitCount += 1

			return self.progress.isCancelled ? 0 : 1
		}

		gifski.setWriteCallback { [weak self] bufferLength, bufferPointer in
			guard let self = self else {
				return 0
			}

			self.gifData.append(bufferPointer, count: bufferLength)

			return 0
		}

		DispatchQueue.global(qos: .utility).async { [weak self] in
			self?.generateData(
				for: conversion,
				isEstimation: isEstimation,
				jobKey: jobKey,
				completionHandler: completionHandlerOnce
			)
		}
	}

	/// Generates GIF data for the provided conversion.
	/// - Parameters:
	///   - conversion: The source information of the conversion.
	///   - isEstimation: Whether the frame is part of a size estimation job.
	///   - jobKey: The string used to identify the current conversion job.
	///   - completionHandler: Closure called when the data conversion completes or an error is encountered.
	private func generateData(
		for conversion: Conversion,
		isEstimation: Bool,
		jobKey: String,
		completionHandler: @escaping (Result<Data, Error>) -> Void
	) {
		let generator: AVAssetImageGenerator
		var times: [CMTime]

		switch imageGenerator(for: conversion, jobKey: jobKey) {
		case .success(let result):
			generator = result.generator
			times = result.times

		case .failure(let error):
			completionHandler(.failure(error))
			return
		}

		// TODO: The whole estimation thing should be split out into a separate method and the things that are shared should also be split out.
		if isEstimation {
			let originalCount = times.count

			if originalCount > 25 {
				times = times
					.chunked(by: 5)
					.sample(length: 5)
					.flatten()
			}

			sizeMultiplierForEstimation = Double(originalCount) / Double(times.count)
		}

		progress.cancellationHandler = generator.cancelAllCGImageGeneration
		progress.totalUnitCount = Int64(times.count)

		let startTime = times.first?.seconds ?? 0

		generator.generateCGImagesAsynchronously(forTimePoints: times) { [weak self] imageResult in
			guard let self = self, !self.progress.isCancelled else {
				completionHandler(.failure(.cancelled))
				return
			}

			let frameResult = self.processFrame(
				for: imageResult,
				at: startTime,
				isEstimation: isEstimation,
				jobKey: jobKey
			)

			switch frameResult {
			case .success(let finished):
				if finished {
					let result = Result<Data, Swift.Error> {
						try self.gifski?.finish()
						return self.gifData
					}
					.mapError(Error.writeFailed)

					completionHandler(result)
				}

			case .failure(let error):
				completionHandler(.failure(error))
			}
		}
	}

	/// Creates an image generator for the provided conversion.
	/// - Parameters:
	///   - conversion: The conversion source of the image generator.
	///   - jobKey: The string used to identify the current conversion job.
	/// - Returns: An AVAssetImageGenerator along with the times of the frames requested by the conversion.
	private func imageGenerator(
		for conversion: Conversion,
		jobKey: String
	) -> Result<(generator: AVAssetImageGenerator, times: [CMTime]), Error> {
		let asset = AVURLAsset(
			url: conversion.video,
			options: [
				AVURLAssetPreferPreciseDurationAndTimingKey: true
			]
		)

		record(
			jobKey: jobKey,
			key: "Is readable?",
			value: asset.isReadable
		)
		record(
			jobKey: jobKey,
			key: "First video track",
			value: asset.firstVideoTrack
		)
		record(
			jobKey: jobKey,
			key: "First video track time range",
			value: asset.firstVideoTrack?.timeRange
		)
		record(
			jobKey: jobKey,
			key: "Duration",
			value: asset.duration.seconds
		)
		record(
			jobKey: jobKey,
			key: "AVAsset debug info",
			value: asset.debugInfo
		)

		guard
			asset.isReadable,
			let assetFrameRate = asset.frameRate,
			let firstVideoTrack = asset.firstVideoTrack,

			// We use the duration of the first video track since the total duration of the asset can actually be longer than the video track. If we use the total duration and the video is shorter, we'll get errors in `generateCGImagesAsynchronously` (#119).
			// We already extract the video into a new asset in `VideoValidator` if the first video track is shorter than the asset duration, so the handling here is not strictly necessary but kept just to be safe.
			let videoTrackRange = firstVideoTrack.timeRange.range
		else {
			// This can happen if the user selects a file, and then the file becomes
			// unavailable or deleted before the "Convert" button is clicked.
			return .failure(.unreadableFile)
		}

		record(
			jobKey: jobKey,
			key: "AVAsset debug info2",
			value: asset.debugInfo
		)

		let generator = AVAssetImageGenerator(asset: asset)
		generator.appliesPreferredTrackTransform = true

		// This improves the performance a little bit.
		if let dimensions = conversion.dimensions {
			generator.maximumSize = CGSize(widthHeight: dimensions.longestSide)
		}

		// Even though we enforce a minimum of 5 FPS in the GUI, a source video could have lower FPS, and we should allow that.
		var fps = (conversion.frameRate.map { Double($0) } ?? assetFrameRate).clamped(to: 0.1...Constants.allowedFrameRate.upperBound)
		fps = min(fps, assetFrameRate)

		print("FPS:", fps)

		// `.zero` tolerance is much slower and fails a lot on macOS 11. (macOS 11.1)
		if #available(macOS 11, *) {
			let tolerance = CMTime(seconds: 0.5 / fps, preferredTimescale: .video)
			generator.requestedTimeToleranceBefore = tolerance
			generator.requestedTimeToleranceAfter = tolerance
		} else {
			generator.requestedTimeToleranceBefore = .zero
			generator.requestedTimeToleranceAfter = .zero
		}

		let videoRange = conversion.timeRange?.clamped(to: videoTrackRange) ?? videoTrackRange
		let startTime = videoRange.lowerBound
		let duration = videoRange.length
		let frameCount = Int(duration * fps)

		guard frameCount >= 2 else {
			return .failure(.notEnoughFrames(frameCount))
		}

		print("Frame count:", frameCount)

		let frameStep = 1 / fps
		let timescale = asset.duration.timescale
		let frameForTimes: [CMTime] = (0..<frameCount).map { index in
			let presentationTimestamp = startTime + (frameStep * Double(index))
			return CMTime(
				seconds: presentationTimestamp,
				preferredTimescale: timescale
			)
		}

		record(
			jobKey: jobKey,
			key: "fps",
			value: fps
		)
		record(
			jobKey: jobKey,
			key: "videoRange",
			value: videoRange
		)
		record(
			jobKey: jobKey,
			key: "frameCount",
			value: frameCount
		)
		record(
			jobKey: jobKey,
			key: "frameForTimes",
			value: frameForTimes.map(\.seconds)
		)

		return .success((generator, frameForTimes))
	}

	/// Generates image data from an image frame and sends that data to the Gifski image API for processing.
	/// - Parameters:
	///   - result: The image size
	///   - startTime: The start time of all the frames being processed. (not the time of the current frame).
	///   - isEstimation: Whether the frame is part of a size estimation job.
	///   - jobKey: The string used to identify the current conversion job.
	/// - Returns: A result containing if an error occurred or if the frame is the last frame in the conversion.
	private func processFrame(
		for result: Result<AVAssetImageGenerator.CompletionHandlerResult, Swift.Error>,
		at startTime: TimeInterval,
		isEstimation: Bool,
		jobKey: String
	) -> Result<Bool, Error> {
		switch result {
		case .success(let result):
			progress.totalUnitCount = Int64(result.totalCount)

			// This happens if the last frame in the video failed to be generated.
			if result.isFinishedIgnoreImage {
				return .success(true)
			}

			if !isEstimation, result.completedCount == 1 {
				record(
					jobKey: jobKey,
					key: "CGImage",
					value: result.image.debugInfo
				)
			}

			let pixels: CGImage.Pixels
			do {
				pixels = try result.image.pixels(as: .argb, premultiplyAlpha: false)
			} catch {
				return .failure(.generateFrameFailed(error))
			}

			do {
				try gifski?.addFrame(
					pixelFormat: .argb,
					frameNumber: result.completedCount - 1,
					width: pixels.width,
					height: pixels.height,
					bytesPerRow: pixels.bytesPerRow,
					pixels: pixels.bytes,
					presentationTimestamp: max(0, result.actualTime.seconds - startTime)
				)
			} catch {
				return .failure(.addFrameFailed(error))
			}

			return .success(result.isFinished)
		case .failure where result.isCancelled:
			return .failure(.cancelled)
		case .failure(let error):
			return .failure(.generateFrameFailed(error))
		}
	}

	func cancel() {
		progress?.cancel()
	}
}

private func record(jobKey: String, key: String, value: Any?) {
	debugPrint("\(jobKey): \(key): \(value ?? "nil")")
	Crashlytics.record(
		key: "\(jobKey): \(key)",
		value: value
	)
}
