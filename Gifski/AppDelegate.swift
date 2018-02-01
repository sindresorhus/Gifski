import Cocoa
import AVFoundation

extension AVAssetImageGenerator {
	func generateCGImagesAsynchronouslyForTimePoints(_ timePoints: [CMTime], completionHandler: @escaping AVAssetImageGeneratorCompletionHandler) {
		let times = timePoints.map { NSValue(time: $0) }
		generateCGImagesAsynchronously(forTimes: times, completionHandler: completionHandler)
	}
}

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	@IBOutlet private weak var window: NSWindow!
	var g: OpaquePointer!

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return true
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		gifski(inputFile: URL(fileURLWithPath: "/Users/sindresorhus/dev/private/Gifski problem demo/test.mp4"), outputFile: URL(fileURLWithPath: "/Users/sindresorhus/dev/private/Gifski problem demo/test.gif"))
	}

	func gifski(inputFile: URL, outputFile: URL) {
		var settings = GifskiSettings(width: 0, height: 0, quality: 100, once: false, fast: false)
		let g = gifski_new(&settings)
		self.g = g

		let asset = AVURLAsset(url: inputFile, options: nil)
		let generator = AVAssetImageGenerator(asset: asset)
		generator.requestedTimeToleranceAfter = kCMTimeZero
		generator.requestedTimeToleranceBefore = kCMTimeZero

		let FPS = 24
		let frameCount = Int(asset.duration.seconds) * FPS
		var frameForTimes = [CMTime]()

//		for i in 0..<frameCount {
//			frameForTimes.append(CMTimeMake(Int64(i), Int32(FPS)))
//		}

		frameForTimes.append(CMTimeMake(1, Int32(FPS)))
		frameForTimes.append(CMTimeMake(2, Int32(FPS)))
		frameForTimes.append(CMTimeMake(3, Int32(FPS)))
		frameForTimes.append(CMTimeMake(4, Int32(FPS)))

		// FIXME: Hangs when this is enabled
		// frameForTimes.append(CMTimeMake(5, Int32(FPS)))

		gifski_set_progress_callback(g) { isDone in
			print("isDone", isDone)

			return 1
		}

		var i = 0

		generator.generateCGImagesAsynchronouslyForTimePoints(frameForTimes) { _, image, _, _, error in
			guard let image = image, error == nil else {
				fatalError("Error with image \(i): \(error!)")
			}

			let buffer = CFDataGetBytePtr(image.dataProvider!.data)

			// TODO: Figure out how I can run this concurrently with GCD
			let result = gifski_add_frame_rgba(g, UInt32(i), UInt32(image.width), UInt32(image.height), buffer, UInt16(100 / FPS))
			precondition(result == GIFSKI_OK, String(describing: result))

			print("Frame:", i)

			i += 1

			if i == frameForTimes.count {
				self.done(outputFile: outputFile)
			}
		}
	}

	func done(outputFile: URL) {
		gifski_end_adding_frames(g)
		gifski_write(g, outputFile.path)
		gifski_drop(g)
	}
}
