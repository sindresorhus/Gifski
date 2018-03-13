import Foundation
import AVFoundation

final class Gifski {
	enum Error: LocalizedError {
		case invalidSettings
		case generateFrameFailed
		case addFrameFailed(GifskiWrapperError)
		case endAddingFramesFailed(GifskiWrapperError)
		case writeFailed(GifskiWrapperError)

		var errorDescription: String? {
			switch self {
			case .invalidSettings:
				return "Invalid settings"
			case .generateFrameFailed:
				return "Failed to generate frame"
			case .addFrameFailed(let error):
				return "Failed to add frame, with underlying error: \(error.localizedDescription)"
			case .endAddingFramesFailed(let error):
				return "Failed to end adding frames, with underlying error: \(error.localizedDescription)"
			case .writeFailed(let error):
				return "Failed to write to output, with underlying error: \(error.localizedDescription)"
			}
		}
	}

	/**
	- parameters:
	- frameRate: Clamped to 5...30. Uses the frame rate of `input` if not specified.
	*/
	struct Conversion {
		let input: URL
		let output: URL
		let quality: Double
		let dimensions: CGSize?
		let frameRate: Int?

		init(input: URL, output: URL, quality: Double = 1, dimensions: CGSize? = nil, frameRate: Int? = nil) {
			self.input = input
			self.output = output
			self.quality = quality
			self.dimensions = dimensions
			self.frameRate = frameRate
		}
	}

	static func run(_ conversion: Conversion, completionHandler: ((Error?) -> Void)?) {
		let settings = GifskiSettings(
			width: UInt32(conversion.dimensions?.width ?? 0),
			height: UInt32(conversion.dimensions?.height ?? 0),
			quality: UInt8(conversion.quality * 100),
			once: false,
			fast: false
		)

		guard let g = GifskiWrapper(settings: settings) else {
			completionHandler?(.invalidSettings)
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

			let fps = (conversion.frameRate.map { Double($0) } ?? asset.videoMetadata!.frameRate).clamped(to: 5...30)
			let frameCount = Int(asset.duration.seconds * fps)
			progress.totalUnitCount = Int64(frameCount)

			var frameForTimes = [CMTime]()
			for i in 0..<frameCount {
				frameForTimes.append(CMTime(seconds: (1 / fps) * Double(i), preferredTimescale: .video))
			}

			var frameIndex = 0
			generator.generateCGImagesAsynchronously(forTimePoints: frameForTimes) { _, image, _, _, error in
				guard let image = image,
					let data = image.dataProvider?.data,
					let buffer = CFDataGetBytePtr(data)
				else {
					completionHandler?(.generateFrameFailed)
					return
				}

				do {
					try g.addFrameARGB(
						index: UInt32(frameIndex),
						width: UInt32(image.width),
						bytesPerRow: UInt32(image.bytesPerRow),
						height: UInt32(image.height),
						pixels: buffer,
						delay: UInt16(100 / fps)
					)
				} catch {
					completionHandler?(.addFrameFailed(error as! GifskiWrapperError))
					return
				}

				frameIndex += 1

				do {
					if frameIndex == frameForTimes.count {
						try g.endAddingFrames()
					}
				} catch {
					completionHandler?(.endAddingFramesFailed(error as! GifskiWrapperError))
					return
				}
			}

			do {
				try g.write(path: conversion.output.path)
				completionHandler?(nil)
			} catch {
				completionHandler?(.writeFailed(error as! GifskiWrapperError))
			}
		}
	}
}
