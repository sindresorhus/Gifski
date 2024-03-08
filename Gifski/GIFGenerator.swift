import Foundation
import AVFoundation

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
		- jobKey: The string used to identify the current conversion job.
		- completionHandler: Closure called when the data conversion completes or an error is encountered.
	*/
	private func generateData(
		for conversion: Conversion,
		isEstimation: Bool,
		onProgress: @escaping (Double) -> Void
	) async throws -> Data {
		var (generator, times, frameRate) = try await imageGenerator(for: conversion)

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

		let totalFrameCount = totalFrameCount(for: conversion, sourceFrameCount: times.count)

		var completedFrameCount = 0
		gifski?.onProgress = {
			let progress = Double(completedFrameCount.increment()) / Double(totalFrameCount)
			onProgress(progress.clamped(to: 0...1)) // TODO: For some reason, when we use `bounce`, `totalFrameCount` can be 1 less than `completedFrameCount` on completion.
		}

		// TODO: Use `Duration`.
		let startTime = times.first?.seconds ?? 0

		// TODO: Does it handle cancellation?

		var index = 0
		var previousTime = -100.0 // Just to make sure it doesn't match any timestamp.

		print("Total frame count:", totalFrameCount)

		for await imageResult in generator.images(for: times) {
			try Task.checkCancellation()

			let requestedTime = imageResult.requestedTime

			// `generator.images` returns old frames randomly. For example, after index 7, it would emit index 3 another time. We filter out times that are lower than last. (macOS 14.3)
			guard requestedTime.seconds > previousTime else {
				continue
			}

			previousTime = requestedTime.seconds

			let image = try imageResult.image
			let actualTime = try imageResult.actualTime

			do {
				let frameNumber = index

				if index > 0 {
					assert(actualTime.seconds > 0)
				}

				// TODO: Use a custom executer for this when using Swift 6.
				try gifski?.addFrame(
					image,
					frameNumber: frameNumber,
					presentationTimestamp: max(0, actualTime.seconds - startTime)
				)

				if conversion.bounce {
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

					// Determine the reverse timestamp by finding the expected timestamp (frame number / frame rate) and adjusting for the image generator's slippage (actualTime - requestedTime)
					let expectedReverseTimestamp = TimeInterval(reverseFrameNumber) / TimeInterval(frameRate)
					let timestampSlippage = actualTime - requestedTime
					let actualReverseTimestamp = max(0, expectedReverseTimestamp + timestampSlippage.seconds)

					try gifski?.addFrame(
						image,
						frameNumber: reverseFrameNumber,
						presentationTimestamp: actualReverseTimestamp
					)
				}

				index += 1
			} catch {
				throw Error.addFrameFailed(error)
			}

			await Task.yield() // Give `addFrame` room to start.
		}

		guard let gifski else {
			throw CancellationError()
		}

		return try gifski.finish()
	}

	/**
	Creates an image generator for the provided conversion.

	- Parameters:
		- conversion: The conversion source of the image generator.
	- Returns: An `AVAssetImageGenerator` along with the times of the frames requested by the conversion.
	*/
	private func imageGenerator(for conversion: Conversion) async throws -> (generator: AVAssetImageGenerator, times: [CMTime], frameRate: Int) {
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

		// TODO: Parallelize using `async let`.
		guard
			try await asset.load(.isReadable),
			let assetFrameRate = try await asset.frameRate,
			let firstVideoTrack = try await asset.firstVideoTrack,

			// We use the duration of the first video track since the total duration of the asset can actually be longer than the video track. If we use the total duration and the video is shorter, we'll get errors in `generateCGImagesAsynchronously` (#119).
			// We already extract the video into a new asset in `VideoValidator` if the first video track is shorter than the asset duration, so the handling here is not strictly necessary but kept just to be safe.
			let videoTrackRange = try await firstVideoTrack.load(.timeRange).range
		else {
			// This can happen if the user selects a file, and then the file becomes
			// unavailable or deleted before the "Convert" button is clicked.
			throw Error.unreadableFile
		}
//
//		record(
//			jobKey: jobKey,
//			key: "AVAsset debug info2",
//			value: asset.debugInfo
//		)

		let generator = AVAssetImageGenerator(asset: asset)
		generator.appliesPreferredTrackTransform = true
		generator.requestedTimeToleranceBefore = .zero
		generator.requestedTimeToleranceAfter = .zero

		// We are intentionally not setting a `generator.maximumSize` as it's buggy: https://github.com/sindresorhus/Gifski/pull/278

		// Even though we enforce a minimum of 3 FPS in the GUI, a source video could have lower FPS, and we should allow that.
		var frameRate = (conversion.frameRate.map(Double.init) ?? assetFrameRate).clamped(to: 0.1...Constants.allowedFrameRate.upperBound)
		frameRate = min(frameRate, assetFrameRate)

		print("Video FPS:", frameRate)

		// TODO: Instead of calculating what part of the video to get, we could just trim the actual `AVAssetTrack`.
		let videoRange = conversion.timeRange?.clamped(to: videoTrackRange) ?? videoTrackRange
		let startTime = videoRange.lowerBound
		let duration = videoRange.length
		let frameCount = Int(duration * frameRate)
		let timescale = try await firstVideoTrack.load(.naturalTimeScale) // TODO: Move this to the other `load` call.

		guard frameCount >= 2 else {
			throw Error.notEnoughFrames(frameCount)
		}

		print("Video frame count:", frameCount)

		let frameStep = 1 / frameRate
		var frameForTimes: [CMTime] = (0..<frameCount).map { index in
			let presentationTimestamp = startTime + (frameStep * Double(index))
			return CMTime(
				seconds: presentationTimestamp,
				preferredTimescale: timescale
			)
		}

		// We don't do this when "bounce" is enabled as the bounce calculations are not able to handle this.
		if !conversion.bounce {
			// Ensure we include the last frame. For example, the above might have calculated `[..., 6.25, 6.3]`, but the duration is `6.3647`, so we might miss the last frame if it appears for a short time.
			frameForTimes.append(CMTime(seconds: duration, preferredTimescale: timescale))
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
//			key: "frameForTimes",
//			value: frameForTimes.map(\.seconds)
//		)

		return (generator, frameForTimes, Int(frameRate))
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
	- Parameter frameRate: Clamped to `5...30`. Uses the frame rate of `input` if not specified.
	- Parameter loopGif: Whether output should loop infinitely or not.
	- Parameter bounce: Whether output should bounce or not.
	*/
	struct Conversion: ReflectiveHashable { // TODO
		let asset: AVAsset
		let sourceURL: URL
		var timeRange: ClosedRange<Double>?
		var quality: Double = 1
		var dimensions: (width: Int, height: Int)?
		var frameRate: Int?
		var loop: Gifski.Loop
		var bounce: Bool

		var gifDuration: Duration {
			get async throws {
				// TODO: Make this lazy so it's only used for fallback.
				let fallbackRange = try await asset.firstVideoTrack?.load(.timeRange).range

				guard let duration = (timeRange ?? fallbackRange)?.length else {
					return .zero
				}

				// TODO: Do this when Swift supports async in `??`.
//				guard let duration = (timeRange ?? asset.firstVideoTrack?.timeRange.range)?.length else {
//					return .zero
//				}

				return .seconds(bounce ? (duration * 2) : duration)
			}
		}
	}
}

extension GIFGenerator {
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
				"Invalid settings."
			case .unreadableFile:
				"The selected file is no longer readable."
			case .notEnoughFrames(let frameCount):
				"An animated GIF requires a minimum of 2 frames. Your video contains \(frameCount) frame\(frameCount == 1 ? "" : "s")."
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
