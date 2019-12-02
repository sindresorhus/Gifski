import Cocoa
import AVFoundation
import Crashlytics

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

	// This is carefully nil'd and should remain private.
	private static var gifData: NSMutableData?

	// TODO: Split this method up into smaller methods. It's too large.
	/**
	Converts a movie to GIF

	- Parameter completionHandler: Guaranteed to be called on the main thread
	*/
	static func run(
		_ conversion: Conversion,
		completionHandler: ((Result<Data, Error>) -> Void)?
	) {
		var progress = Progress(parent: .current())

		let completionHandlerOnce = Once().wrap { (_ result: Result<Data, Error>) -> Void in
			gifData = nil // Resetting state

			DispatchQueue.main.async {
				guard !progress.isCancelled else {
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

		gifData = NSMutableData()

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

			guard asset.isReadable else {
				// This can happen if the user selects a file, and then the file becomes
				// unavailable or deleted before the "Convert" button is clicked.
				completionHandlerOnce(.failure(.unreadableFile))
				return
			}

			Crashlytics.record(
				key: "Conversion: AVAsset debug info",
				value: asset.debugInfo
			)

			let generator = AVAssetImageGenerator(asset: asset)
			generator.requestedTimeToleranceAfter = .zero
			generator.requestedTimeToleranceBefore = .zero
			generator.appliesPreferredTrackTransform = true

			progress.cancellationHandler = {
				generator.cancelAllCGImageGeneration()
			}

			let fps = (conversion.frameRate.map { Double($0) } ?? asset.videoMetadata!.frameRate).clamped(to: 5...30)
			let startTime = conversion.timeRange?.lowerBound ?? 0.0
			let duration: Double = {
				if let timeRange = conversion.timeRange {
					return timeRange.upperBound - timeRange.lowerBound
				} else {
					return asset.duration.seconds
				}
			}()
			let frameCount = Int(duration * fps)
			progress.totalUnitCount = Int64(frameCount)

			var frameForTimes = [CMTime]()
			for index in 0..<frameCount {
				frameForTimes.append(CMTime(seconds: startTime + ((1 / fps) * Double(index)), preferredTimescale: .video))
			}

			generator.generateCGImagesAsynchronously(forTimePoints: frameForTimes) { result in
				guard !progress.isCancelled else {
					completionHandlerOnce(.failure(.cancelled))
					return
				}

				switch result {
				case let .success(result):
					let image = result.image

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
							index: UInt32(result.completedCount - 1),
							width: UInt32(image.width),
							bytesPerRow: UInt32(image.bytesPerRow),
							height: UInt32(image.height),
							pixels: buffer,
							delay: UInt16(100 / fps)
						)
					} catch {
						completionHandlerOnce(.failure(.addFrameFailed(error)))
						return
					}

					if result.isFinished {
						do {
							try gifski.finish()
							// Force unwrapping here is safe because we nil gifData in one single place after this.
							completionHandlerOnce(.success(gifData! as Data))
						} catch {
							completionHandlerOnce(.failure(.writeFailed(error)))
						}
					}
				case .failure where result.isCancelled:
					completionHandlerOnce(.failure(.cancelled))
				case let .failure(error):
					// TODO: Remove this when we've been able to track down the issue.
					completionHandlerOnce(.failure(.cancelled))
					DispatchQueue.main.async {
						NSAlert.showModal(
							message: "Gifski was unable generate frames from the video",
							informativeText: "We have been trying to track down this issue for a long time, but we have been unable to reproduce it. It would be awesome if you could send an email to sindresorhus@gmail.com with the video or some information about the video file you tried to convert so we can fix this issue.",
							detailText: "\(error)"
						)
					}

					// completionHandlerOnce(.failure(.generateFrameFailed(error)))
				}
			}
		}
	}
}
