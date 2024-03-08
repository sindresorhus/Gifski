import SwiftUI

// TODO: Actor
final class Gifski {
	enum Loop {
		case forever
		case never
		case count(Int)
	}

	private var wrapper: GifskiWrapper?
	private var frameNumber = 0
	private var data = Data()
	private var hasFinished = false

	var onProgress: (() -> Void)?

	// TODO: Make this when the rest of the app uses more async
//	var progress: AsyncStream<Data> {}

	init(
		dimensions: (width: Int, height: Int)? = nil,
		quality: Double,
		loop: Loop,
		fast: Bool = false
	) throws {
		let loopCount = {
			switch loop {
			case .forever:
				return 0
			case .never:
				return -1
			case .count(let count):
				assert(count > 0) // swiftlint:disable:this empty_count
				return count
			}
		}()

		assert(quality >= 0.1)
		assert(quality <= 1)

		let settings = GifskiSettings(
			width: UInt32(clamping: dimensions?.width ?? 0),
			height: UInt32(clamping: dimensions?.height ?? 0),
			quality: UInt8(clamping: Int((quality * 100).rounded()).clamped(to: 1...100)),
			fast: fast,
			repeat: Int16(clamping: loopCount)
		)

		guard let wrapper = GifskiWrapper(settings) else {
			throw GifskiWrapper.Error.invalidInput
		}

		self.wrapper = wrapper

		wrapper.setErrorMessageCallback {
			SSApp.reportError($0)
		}

		wrapper.setProgressCallback { [weak self] in
			guard let self else {
				return 0
			}

			onProgress?()

			return self.wrapper == nil ? 0 : 1
		}

		wrapper.setWriteCallback { [weak self] bufferLength, bufferPointer in
			guard let self else {
				return 0
			}

			data.append(bufferPointer, count: bufferLength)

			return 0
		}
	}

	deinit {
		_ = try? wrapper?.finish()
	}

	func addFrame(
		_ image: CGImage,
		frameNumber: Int,
		presentationTimestamp: Double
	) throws {
		guard let wrapper else {
			assertionFailure("Called “addFrame” after it finished.")
			throw GifskiWrapper.Error.invalidState
		}

		let pixels = try image.pixels(as: .rgba, premultiplyAlpha: false)

		try wrapper.addFrame(
			pixelFormat: .rgba,
			frameNumber: frameNumber,
			width: pixels.width,
			height: pixels.height,
			bytesPerRow: pixels.bytesPerRow,
			pixels: pixels.bytes,
			presentationTimestamp: presentationTimestamp
		)
	}

	func addFrame(
		_ image: CGImage,
		presentationTimestamp: Double
	) throws {
		try addFrame(
			image,
			frameNumber: frameNumber,
			presentationTimestamp: presentationTimestamp
		)

		frameNumber += 1
	}

	func finish() throws -> Data {
		guard let wrapper else {
			assertionFailure("Called “finish” more than once.")
			throw GifskiWrapper.Error.invalidState
		}

		try wrapper.finish()
		self.wrapper = nil
		return data
	}
}
