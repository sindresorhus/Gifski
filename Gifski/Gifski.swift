import Foundation
import AVFoundation

final class Gifski {
	enum Error: LocalizedError {
		case invalidSettings
		case generateFrameFailed(Swift.Error)
		case addFrameFailed(GifskiWrapperError)
		case endAddingFramesFailed(GifskiWrapperError)
		case writeFailed(GifskiWrapperError)
		case cancelled

		var errorDescription: String? {
			switch self {
			case .invalidSettings:
				return "Invalid settings"
			case let .generateFrameFailed(error):
				return "Failed to generate frame: \(error.localizedDescription)"
			case let .addFrameFailed(error):
				return "Failed to add frame, with underlying error: \(error.localizedDescription)"
			case let .endAddingFramesFailed(error):
				return "Failed to end adding frames, with underlying error: \(error.localizedDescription)"
			case let .writeFailed(error):
				return "Failed to write to output, with underlying error: \(error.localizedDescription)"
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
		let completionHandlerOnce = Once().wrap { error in
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

		guard let g = GifskiWrapper(settings: settings) else {
			completionHandlerOnce(.invalidSettings)
			return
		}

		var progress = Progress(parent: .current())
		progress.fileURL = conversion.output

		g.setProgressCallback(context: &progress) { context in
			let progress = context!.assumingMemoryBound(to: Progress.self).pointee
			progress.completedUnitCount += 1
			return progress.isCancelled ? 0 : 1
		}

		DispatchQueue.global(qos: .utility).async {
			progress.publish()
			defer { progress.unpublish() }

			let asset = AVURLAsset(url: conversion.input, options: nil)
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
			for i in 0..<frameCount {
				frameForTimes.append(CMTime(seconds: (1 / fps) * Double(i), preferredTimescale: .video))
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
						completionHandlerOnce(.generateFrameFailed("Could not get byte pointer of image data provider"))
						return
					}

					do {
						try g.addFrameARGB(
							index: UInt32(result.completedCount - 1),
							width: UInt32(image.width),
							bytesPerRow: UInt32(image.bytesPerRow),
							height: UInt32(image.height),
							pixels: buffer,
							delay: UInt16(100 / fps)
						)
					} catch {
						completionHandlerOnce(.addFrameFailed(error as! GifskiWrapperError))
						return
					}

					if result.isFinished {
						do {
							try g.endAddingFrames()
						} catch {
							completionHandlerOnce(.endAddingFramesFailed(error as! GifskiWrapperError))
						}
					}
				case .failure where result.isCancelled:
					completionHandlerOnce(.cancelled)
				case let .failure(error):
					completionHandlerOnce(.generateFrameFailed(error))
				}
			}

			do {
				try g.write(path: conversion.output.path)
				completionHandlerOnce(nil)
			} catch {
				// TODO: Figure out how to not get a write error when the process was simply cancelled.
				// To reproduce, remove the guard-statement, and try cancelling at 80-95%.
				guard !progress.isCancelled else {
					completionHandlerOnce(.cancelled)
					return
				}

				completionHandlerOnce(.writeFailed(error as! GifskiWrapperError))
			}
		}
	}
}
