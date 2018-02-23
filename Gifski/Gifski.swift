import Foundation
import AVFoundation

final class Gifski {
	private(set) var isRunning = false
	private var progress: Progress!

	// `progress.fractionCompleted` is KVO-compliant, but we expose this for convenience
	var onProgress: ((_ progress: Double) -> Void)?

	/**
	- parameters:
		- frameRate: Clamped to 5...30. Uses the frame rate of `inputUrl` if not specified.
	*/
	@discardableResult
	func convertFile(
		_ inputUrl: URL,
		outputUrl: URL,
		quality: Double = 1,
		dimensions: CGSize? = nil,
		frameRate: Int? = nil
	) -> Progress {
		/// TODO: Find a better way to handle this
		guard !isRunning else {
			fatalError("Create a new instance if you want to run multiple conversions at once")
		}

		isRunning = true

		progress = Progress(parent: nil, userInfo: [.fileURLKey: outputUrl])
		progress.fileURL = outputUrl

		var settings = GifskiSettings(
			width: UInt32(dimensions?.width ?? 0),
			height: UInt32(dimensions?.height ?? 0),
			quality: UInt8(quality * 100),
			once: false,
			fast: false
		)
		let g = gifski_new(&settings)

		let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
		gifski_set_progress_callback(g, { user_data in
			let mySelf = Unmanaged<Gifski>.fromOpaque(user_data!).takeUnretainedValue()

			DispatchQueue.main.async {
				mySelf.progress.completedUnitCount += 1
				mySelf.onProgress?(mySelf.progress.fractionCompleted)
				mySelf.isRunning = !mySelf.progress.isFinished
			}

			return mySelf.progress.isCancelled ? 0 : 1
		}, context)

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
				guard let image = image, error == nil else {
					fatalError("Error with image \(frameIndex): \(error!)")
				}

				let buffer = CFDataGetBytePtr(image.dataProvider!.data)

				let result = gifski_add_frame_argb(
					g,
					UInt32(frameIndex),
					UInt32(image.width),
					UInt32(image.bytesPerRow),
					UInt32(image.height),
					buffer,
					UInt16(100 / fps)
				)
				precondition(result == GIFSKI_OK, String(describing: result))

				frameIndex += 1

				if frameIndex == frameForTimes.count {
					gifski_end_adding_frames(g)
				}
			}

			gifski_write(g, outputUrl.path)
			gifski_drop(g)
		}

		return progress
	}
}
