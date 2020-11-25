import Cocoa
import AVFoundation
import FirebaseCrashlytics

var conversionCount = 0

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
		var loopGif: Bool = true
		var timesShown: Int = 9999
	}

	private var gifData = NSMutableData()
	private var progress: Progress!
	private var gifski: GifskiWrapper?

	var sizeMultiplierForEstimation = 1.0

	deinit {
		cancel()
	}

	// TODO: Split this method up into smaller methods. It's too large.
	/**
	Converts a movie to GIF.

	- Parameter completionHandler: Guaranteed to be called on the main thread
	*/
	func run(
		_ conversion: Conversion,
		isEstimation: Bool,
		completionHandler: ((Result<Data, Error>) -> Void)?
	) {
		// For debugging.
		conversionCount += 1
		let debugKey = "Conversion \(conversionCount)"

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
					completionHandler?(.failure(.cancelled))
					return
				}

				completionHandler?(result)
			}
		}

		let settings = GifskiSettings(
			width: UInt32(conversion.dimensions?.width ?? 0),
			height: UInt32(conversion.dimensions?.height ?? 0),
			quality: UInt8(conversion.quality * 100),
			once: !conversion.loopGif,
			fast: false,
			times_shown: UInt16(conversion.timesShown)
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

			self.gifData.append(bufferPointer, length: bufferLength)

			return 0
		}

		DispatchQueue.global(qos: .utility).async {
			let asset = AVURLAsset(
				url: conversion.video,
				options: [
					AVURLAssetPreferPreciseDurationAndTimingKey: true
				]
			)

			Crashlytics.record(
				key: "\(debugKey): Is readable?",
				value: asset.isReadable
			)
			Crashlytics.record(
				key: "\(debugKey): First video track",
				value: asset.firstVideoTrack
			)
			Crashlytics.record(
				key: "\(debugKey): First video track time range",
				value: asset.firstVideoTrack?.timeRange
			)
			Crashlytics.record(
				key: "\(debugKey): Duration",
				value: asset.duration.seconds
			)
			Crashlytics.record(
				key: "\(debugKey): AVAsset debug info",
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
				completionHandlerOnce(.failure(.unreadableFile))
				return
			}

			Crashlytics.record(
				key: "\(debugKey): AVAsset debug info2",
				value: asset.debugInfo
			)

			let generator = AVAssetImageGenerator(asset: asset)
			generator.appliesPreferredTrackTransform = true
			generator.requestedTimeToleranceBefore = .zero
			generator.requestedTimeToleranceAfter = .zero

			self.progress.cancellationHandler = {
				generator.cancelAllCGImageGeneration()
			}

			let fps = (conversion.frameRate.map { Double($0) } ?? assetFrameRate).clamped(to: Constants.allowedFrameRate)
			let videoRange = conversion.timeRange?.clamped(to: videoTrackRange) ?? videoTrackRange
			let startTime = videoRange.lowerBound
			let duration = videoRange.length
			let frameCount = Int(duration * fps)

			guard frameCount >= 2 else {
				completionHandlerOnce(.failure(.notEnoughFrames(frameCount)))
				return
			}

			self.progress.totalUnitCount = Int64(frameCount)

			var frameForTimes = [CMTime]()
			let frameStep = 1 / fps
			for index in 0..<frameCount {
				let presentationTimestamp = startTime + (frameStep * Double(index))

				frameForTimes.append(
					CMTime(
						seconds: presentationTimestamp,
						preferredTimescale: asset.duration.timescale
					)
				)
			}

			// TODO: The whole estimation thing should be split out into a separate method and the things that are shared should also be split out.
			if isEstimation {
				let originalCount = frameForTimes.count

				if originalCount > 25 {
					frameForTimes = frameForTimes
						.chunked(by: 5)
						.sample(length: 5)
						.flatten()
				}

				self.sizeMultiplierForEstimation = Double(originalCount) / Double(frameForTimes.count)
			}

			Crashlytics.record(
				key: "\(debugKey): fps",
				value: fps
			)
			Crashlytics.record(
				key: "\(debugKey): videoRange",
				value: videoRange
			)
			Crashlytics.record(
				key: "\(debugKey): frameCount",
				value: frameCount
			)
			Crashlytics.record(
				key: "\(debugKey): frameForTimes",
				value: frameForTimes.map(\.seconds)
			)

			generator.generateCGImagesAsynchronously(forTimePoints: frameForTimes) { [weak self] result in
				guard let self = self else {
					return
				}

				guard !self.progress.isCancelled else {
					completionHandlerOnce(.failure(.cancelled))
					return
				}

				switch result {
				case .success(let result):
					self.progress.totalUnitCount = Int64(result.totalCount)
					let image = result.image

					guard let bytePointer = image.bytePointer else {
						completionHandlerOnce(.failure(.generateFrameFailed(
							NSError.appError("Could not get byte pointer of image data provider.")
						)))
						return
					}

					do {
						try gifski.addFrameARGB(
							frameNumber: UInt32(result.completedCount - 1),
							width: UInt32(image.width),
							bytesPerRow: UInt32(image.bytesPerRow),
							height: UInt32(image.height),
							pixels: bytePointer,
							presentationTimestamp: max(0, result.actualTime.seconds - startTime)
						)
					} catch {
						completionHandlerOnce(.failure(.addFrameFailed(error)))
						return
					}

					if result.isFinished {
						do {
							try gifski.finish()
							completionHandlerOnce(.success(self.gifData as Data))
						} catch {
							completionHandlerOnce(.failure(.writeFailed(error)))
						}
					}
				case .failure where result.isCancelled:
					completionHandlerOnce(.failure(.cancelled))
				case .failure(let error):
					completionHandlerOnce(.failure(.generateFrameFailed(error)))
				}
			}
		}
	}

	func cancel() {
		progress?.cancel()
	}
}
