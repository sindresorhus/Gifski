import Cocoa
import AVFoundation
import Crashlytics

var conversionCount = 0

final class Gifski {
	enum Error: LocalizedError {
		case invalidSettings
		case unreadableFile
		case generateFrameFailed(Swift.Error)
		case addFrameFailed(Swift.Error)
		case writeFailed(Swift.Error)
		case cancelled

		var errorDescription: String? {
			switch self {
			case .invalidSettings:
				return "Invalid settings"
			case .unreadableFile:
				return "The selected file is no longer readable"
			case let .generateFrameFailed(error):
				return "Failed to generate frame: \(error.localizedDescription)"
			case let .addFrameFailed(error):
				return "Failed to add frame, with underlying error: \(error.localizedDescription)"
			case let .writeFailed(error):
				return "Failed to write, with underlying error: \(error.localizedDescription)"
			case .cancelled:
				return "The conversion was cancelled"
			}
		}
	}

	struct Conversion {
		let video: URL
		let timeRange: ClosedRange<Double>?
		let quality: Double
		let dimensions: CGSize?
		let frameRate: Int?
		let loopGif: Bool

		// TODO: With Swift 5.1 we can remove the manual `init` and have it synthesized.
		/**
		- Parameter frameRate: Clamped to `5...30`. Uses the frame rate of `input` if not specified.
		*/
		/**
		- Parameter loopGif: Whether output should loop infinitely or not.
		*/
		init(
			video: URL,
			timeRange: ClosedRange<Double>? = nil,
			quality: Double = 1,
			dimensions: CGSize? = nil,
			frameRate: Int? = nil,
			loopGif: Bool = true
		) {
			self.video = video
			self.timeRange = timeRange
			self.quality = quality
			self.dimensions = dimensions
			self.frameRate = frameRate
			self.loopGif = loopGif
		}
	}

	private var gifData = NSMutableData()
	private var progress: Progress!

	// TODO: Split this method up into smaller methods. It's too large.
	/**
	Converts a movie to GIF

	- Parameter completionHandler: Guaranteed to be called on the main thread
	*/
	func run(
		_ conversion: Conversion,
		completionHandler: ((Result<Data, Error>) -> Void)?
	) {
		// For debugging.
		conversionCount += 1
		let debugKey = "Conversion \(conversionCount)"

		progress = Progress(parent: .current())

		let completionHandlerOnce = Once().wrap { (_ result: Result<Data, Error>) -> Void in
			DispatchQueue.main.async {
				guard !self.progress.isCancelled else {
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
			fast: false
		)

		guard let gifski = GifskiWrapper(settings: settings) else {
			completionHandlerOnce(.failure(.invalidSettings))
			return
		}

		gifski.setProgressCallback(context: &progress) { context in
			let progress = context!.assumingMemoryBound(to: Progress.self).pointee
			progress.completedUnitCount += 1
			return progress.isCancelled ? 0 : 1
		}

		gifski.setWriteCallback(context: &gifData) { bufferLength, bufferPointer, context in
			guard
				bufferLength > 0,
				let bufferPointer = bufferPointer
			else {
				return 0
			}

			let data = context!.assumingMemoryBound(to: NSMutableData.self).pointee
			data.append(bufferPointer, length: bufferLength)

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
			generator.requestedTimeToleranceAfter = .zero
			generator.requestedTimeToleranceBefore = .zero
			generator.appliesPreferredTrackTransform = true

			self.progress.cancellationHandler = {
				generator.cancelAllCGImageGeneration()
			}

			let fps = (conversion.frameRate.map { Double($0) } ?? assetFrameRate).clamped(to: Constants.allowedFrameRate)
			let videoRange = conversion.timeRange?.clamped(to: videoTrackRange) ?? videoTrackRange
			let startTime = videoRange.lowerBound
			let duration = videoRange.length

			let frameCount = Int(duration * fps)
			self.progress.totalUnitCount = Int64(frameCount)

			var frameForTimes = [CMTime]()
			let frameStep = 1 / fps
			for index in 0..<frameCount {
				let presentationTimestamp = startTime + (frameStep * Double(index))

				frameForTimes.append(
					CMTime(
						seconds: presentationTimestamp,
						preferredTimescale: .video
					)
				)
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
				value: frameForTimes.map { $0.seconds }
			)

			var frameNumber = 0
			var previousActualTime: CMTime?

			generator.generateCGImagesAsynchronously(forTimePoints: frameForTimes) { [weak self] result in
				guard let self = self else {
					return
				}

				guard !self.progress.isCancelled else {
					completionHandlerOnce(.failure(.cancelled))
					return
				}

				switch result {
				case let .success(result):
					let image = result.image

					func finalizeIfNeeded() {
						if result.isFinished {
							do {
								try gifski.finish()
								completionHandlerOnce(.success(self.gifData as Data))
							} catch {
								completionHandlerOnce(.failure(.writeFailed(error)))
							}
						}
					}

					// Skip duplicate frames.
					guard result.actualTime != previousActualTime else {
						self.progress.totalUnitCount -= 1
						finalizeIfNeeded()
						return
					}

					previousActualTime = result.actualTime

					guard
						let data = image.dataProvider?.data,
						let buffer = CFDataGetBytePtr(data)
					else {
						completionHandlerOnce(.failure(.generateFrameFailed(
							NSError.appError(message: "Could not get byte pointer of image data provider")
						)))
						return
					}

					do {
						try gifski.addFrameARGB(
							frameNumber: UInt32(frameNumber),
							width: UInt32(image.width),
							bytesPerRow: UInt32(image.bytesPerRow),
							height: UInt32(image.height),
							pixels: buffer,
							presentationTimestamp: result.requestedTime.seconds
						)

						frameNumber += 1
					} catch {
						completionHandlerOnce(.failure(.addFrameFailed(error)))
						return
					}

					finalizeIfNeeded()
				case .failure where result.isCancelled:
					completionHandlerOnce(.failure(.cancelled))
				case let .failure(error):
					completionHandlerOnce(.failure(.generateFrameFailed(error)))
				}
			}
		}
	}
}
