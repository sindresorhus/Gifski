import Foundation
import AVFoundation

final class Gifski {
	private(set) var isRunning = false
	private var progress: Progress!
	private var observation: NSKeyValueObservation?

	// `progress.fractionCompleted` is KVO-compliant, but we expose this for convenience
	var onProgress: ((_ progress: Progress) -> Void)?

	/**
	- parameters:
		- frameRate: Clamped to 5...30. Uses the frame rate of `inputUrl` if not specified.
	*/
	func convertFile(
		_ inputUrl: URL,
		outputUrl: URL,
		quality: Double = 1,
		dimensions: CGSize? = nil,
		frameRate: Int? = nil
	) {
		/// TODO: Find a better way to handle this
		guard !isRunning else {
			fatalError("Create a new instance if you want to run multiple conversions at once")
		}

		isRunning = true

		progress = Progress(parent: .current(), userInfo: [.fileURLKey: outputUrl])
		progress.fileURL = outputUrl
		progress.publish()

		observation = progress.observe(\.fractionCompleted) { progress, _ in
			DispatchQueue.main.async {
				self.onProgress?(progress)
				self.isRunning = !progress.isFinished
			}
		}

		let settings = GifskiSettings(
			width: UInt32(dimensions?.width ?? 0),
			height: UInt32(dimensions?.height ?? 0),
			quality: UInt8(quality * 100),
			once: false,
			fast: false
		)
		guard let g = GifskiWrapper(settings: settings) else {
			fatalError("Gifski instantiated with invalid settings")
		}

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
			self.progress.totalUnitCount = Int64(frameCount)

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
					fatalError("Error with image \(frameIndex): \(error!)")
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

					frameIndex += 1

					if frameIndex == frameForTimes.count {
						try g.endAddingFrames()
					}
				} catch {
					fatalError(error.localizedDescription)
				}
			}

			do {
				try g.write(path: outputUrl.path)
			} catch {
				fatalError(error.localizedDescription)
			}
			self.progress.unpublish()
		}
	}
}
