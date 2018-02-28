import Foundation
import AVFoundation

enum Result {
	case success
	case error(GifskiConversionError)
}

enum GifskiConversionError: LocalizedError {
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
			return "Failed to write to output, with underlying errror: \(error.localizedDescription)"
		}
	}
}

final class Gifski {

	/**
	- parameters:
		- frameRate: Clamped to 5...30. Uses the frame rate of `inputUrl` if not specified.
	*/
	static func convert(
		fileAt inputUrl: URL,
		outputTo outputUrl: URL,
		withQuality quality: Double = 1,
		dimensions: CGSize? = nil,
		frameRate: Int? = nil,
		completionHandler: ((Result) -> Void)?
	) {
		let settings = GifskiSettings(
			width: UInt32(dimensions?.width ?? 0),
			height: UInt32(dimensions?.height ?? 0),
			quality: UInt8(quality * 100),
			once: false,
			fast: false
		)
		guard let g = GifskiWrapper(settings: settings) else {
			completionHandler?(.error(.invalidSettings))
			return
		}

		var progress = Progress(parent: .current(), userInfo: [.fileURLKey: outputUrl])
		progress.fileURL = outputUrl
		progress.publish()

		g.setProgressCallback(context: &progress) { context in
			let progress = context!.assumingMemoryBound(to: Progress.self).pointee
			progress.completedUnitCount += 1
			return progress.isCancelled ? 0 : 1
		}

		DispatchQueue.global(qos: .utility).async {
			let asset = AVURLAsset(url: inputUrl, options: nil)
			let generator = AVAssetImageGenerator(asset: asset)
			generator.requestedTimeToleranceAfter = .zero
			generator.requestedTimeToleranceBefore = .zero

			let fps = (frameRate.map { Double($0) } ?? asset.videoMetadata!.frameRate).clamped(to: 5...30)
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
					let buffer = CFDataGetBytePtr(data),
					error == nil
				else {
					completionHandler?(.error(.generateFrameFailed))
					progress.unpublish()
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
					completionHandler?(.error(.addFrameFailed(error as! GifskiWrapperError)))
					progress.unpublish()
					return
				}

				frameIndex += 1

				do {
					if frameIndex == frameForTimes.count {
						try g.endAddingFrames()
					}
				} catch {
					completionHandler?(.error(.endAddingFramesFailed(error as! GifskiWrapperError)))
					progress.unpublish()
					return
				}
			}

			do {
				try g.write(path: outputUrl.path)
				completionHandler?(.success)
			} catch {
				completionHandler?(.error(.writeFailed(error as! GifskiWrapperError)))
			}
			progress.unpublish()
		}
	}
}
