import Foundation
import AVFoundation
import Crashlytics

final class Gifski {
	enum Error: LocalizedError {
		case invalidSettings
		case generateFrameFailed(Swift.Error)
		case addFrameFailed(Swift.Error)
		case writeFailed(Swift.Error)
		case cancelled

		var errorDescription: String? {
			switch self {
			case .invalidSettings:
				return "Invalid settings"
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
		let input: URL
		let output: URL
		let quality: Double
		let dimensions: CGSize?
		let frameRate: Int?

		/**
		- Parameter frameRate: Clamped to 5...30. Uses the frame rate of `input` if not specified.
		*/
		init(input: URL, output: URL, quality: Double = 1, dimensions: CGSize? = nil, frameRate: Int? = nil) {
			self.input = input
			self.output = output
			self.quality = quality
			self.dimensions = dimensions
			self.frameRate = frameRate
		}
	}

	/**
	Converts a movie to GIF

	- Parameter completionHandler: Guaranteed to be called on the main thread
	*/
	static func run(_ conversion: Conversion, completionHandler: ((Error?) -> Void)?) {
		var progress = Progress(parent: .current())
		progress.fileURL = conversion.output

		let completionHandlerOnce = Once().wrap { (error: Error?) -> Void in
			if error != nil {
				progress.cancel()
			}

			DispatchQueue.main.async {
				completionHandler?(error)
			}
		}

		let settings = GifskiSettings(
			width: UInt32(conversion.dimensions?.width ?? 0),
			height: UInt32(conversion.dimensions?.height ?? 0),
			quality: UInt8(conversion.quality * 100),
			once: false,
			fast: false
		)

		guard let gifski = GifskiWrapper(settings: settings) else {
			completionHandlerOnce(.invalidSettings)
			return
		}

		do {
			try gifski.setFileOutput(path: conversion.output.path)
		} catch {
			completionHandlerOnce(.writeFailed(error))
			return
		}

		gifski.setProgressCallback(context: &progress) { context in
			let progress = context!.assumingMemoryBound(to: Progress.self).pointee
			progress.completedUnitCount += 1
			return progress.isCancelled ? 0 : 1
		}

		DispatchQueue.global(qos: .utility).async {
			let asset = AVURLAsset(
				url: conversion.input,
				options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
			)

			guard asset.isReadable else {
				// This can happen if the user selects a file, and then the file becomes
				// unavailable or deleted before the "Convert" button is clicked.
				completionHandlerOnce(.generateFrameFailed(
					NSError.appError(message: "The selected file is no longer readable")
				))
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
			let frameCount = Int(asset.duration.seconds * fps)
			progress.totalUnitCount = Int64(frameCount)

			var frameForTimes = [CMTime]()
			for index in 0..<frameCount {
				frameForTimes.append(CMTime(seconds: (1 / fps) * Double(index), preferredTimescale: .video))
			}

			generator.generateCGImagesAsynchronously(forTimePoints: frameForTimes) { result in
				guard !progress.isCancelled else {
					completionHandlerOnce(.cancelled)
					return
				}

				switch result {
				case let .success(result):
					let image = result.image

					guard
						let data = image.dataProvider?.data,
						let buffer = CFDataGetBytePtr(data)
					else {
						completionHandlerOnce(.generateFrameFailed(
							NSError.appError(message: "Could not get byte pointer of image data provider")
						))
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
						completionHandlerOnce(.addFrameFailed(error))
						return
					}

					if result.isFinished {
						do {
							try gifski.finish()
							completionHandlerOnce(nil)
						} catch {
							completionHandlerOnce(.writeFailed(error))
						}
					}
				case .failure where result.isCancelled:
					completionHandlerOnce(.cancelled)
				case let .failure(error):
					completionHandlerOnce(.generateFrameFailed(error))
				}
			}
		}
	}
}
