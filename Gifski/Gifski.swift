import Foundation
import AVFoundation

final class Gifski {
	private var frameCount = 0
	private var frameIndex = 0
	private(set) var isRunning = false
	private(set) var progress: Double = 0
	var onProgress: ((_ progress: Double) -> Void)?

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
		guard !isRunning else {
			return
		}

		frameCount = 0
		frameIndex = 0
		isRunning = true

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
				mySelf.frameIndex += 1

				if mySelf.frameIndex == mySelf.frameCount {
					mySelf.isRunning = false
				}

				mySelf.progress = Double(mySelf.frameIndex) / Double(mySelf.frameCount)
				mySelf.onProgress?(mySelf.progress)
			}

			return 1
		}, context)

		DispatchQueue.global(qos: .utility).async {
			let asset = AVURLAsset(url: inputUrl, options: nil)
			let generator = AVAssetImageGenerator(asset: asset)
			generator.requestedTimeToleranceAfter = .zero
			generator.requestedTimeToleranceBefore = .zero

			let fps = (frameRate.map { Double($0) } ?? asset.videoMetadata!.frameRate).clamped(to: 5...30)
			self.frameCount = Int(asset.duration.seconds * fps)

			var frameForTimes = [CMTime]()
			for i in 0..<self.frameCount {
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
	}
}
