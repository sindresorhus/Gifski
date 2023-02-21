import Foundation

// TODO: Make it an actor.
final class GifskiWrapper {
	enum PixelFormat {
		case rgba
		case argb
		case rgb
	}

	typealias ErrorMessageCallback = (String) -> Void
	typealias ProgressCallback = () -> Int
	typealias WriteCallback = (Int, UnsafePointer<UInt8>) -> Int

	private let pointer: OpaquePointer
	private var unmanagedSelf: Unmanaged<GifskiWrapper>!
	private var hasFinished = false
	private var errorMessageCallback: ErrorMessageCallback!
	private var progressCallback: ProgressCallback!
	private var writeCallback: WriteCallback!

	init?(_ settings: GifskiSettings) {
		var settings = settings

		guard let pointer = gifski_new(&settings) else {
			return nil
		}

		self.pointer = pointer

		// We need to keep a strong reference to self so we can ensure it's not deallocated before libgifski finishes writing.
		self.unmanagedSelf = Unmanaged.passRetained(self)
	}

	private func wrap(_ fn: () -> GifskiError) throws {
		let result = fn()

		guard result == GIFSKI_OK else {
			throw Error(rawValue: result.rawValue) ?? .other
		}
	}

	func setErrorMessageCallback(_ callback: @escaping ErrorMessageCallback) {
		guard !hasFinished else {
			return
		}

		errorMessageCallback = callback

		gifski_set_error_message_callback(
			pointer,
			{ message, context in // swiftlint:disable:this opening_brace
				guard
					let message,
					let context
				else {
					return
				}

				let this = Unmanaged<GifskiWrapper>.fromOpaque(context).takeUnretainedValue()
				this.errorMessageCallback(String(cString: message))
			},
			unmanagedSelf.toOpaque()
		)
	}

	func setProgressCallback(_ callback: @escaping ProgressCallback) {
		guard !hasFinished else {
			return
		}

		progressCallback = callback

		gifski_set_progress_callback(
			pointer,
			{ context in // swiftlint:disable:this opening_brace
				guard let context else {
					return 0
				}

				let this = Unmanaged<GifskiWrapper>.fromOpaque(context).takeUnretainedValue()
				return Int32(this.progressCallback())
			},
			unmanagedSelf.toOpaque()
		)
	}

	func setWriteCallback(_ callback: @escaping WriteCallback) {
		guard !hasFinished else {
			return
		}

		writeCallback = callback

		gifski_set_write_callback(
			pointer,
			{ bufferLength, bufferPointer, context in // swiftlint:disable:this opening_brace
				guard
					bufferLength > 0,
					let bufferPointer,
					let context
				else {
					return 0
				}

				let this = Unmanaged<GifskiWrapper>.fromOpaque(context).takeUnretainedValue()
				return Int32(this.writeCallback(bufferLength, bufferPointer))
			},
			unmanagedSelf.toOpaque()
		)
	}

	// swiftlint:disable:next function_parameter_count
	func addFrame(
		pixelFormat: PixelFormat,
		frameNumber: Int,
		width: Int,
		height: Int,
		bytesPerRow: Int,
		pixels: [UInt8],
		presentationTimestamp: Double
	) throws {
		guard !hasFinished else {
			throw Error.invalidState
		}

		try wrap {
			var pixels = pixels

			switch pixelFormat {
			case .rgba:
				return gifski_add_frame_rgba_stride(
					pointer,
					UInt32(frameNumber),
					UInt32(width),
					UInt32(height),
					UInt32(bytesPerRow),
					&pixels,
					presentationTimestamp
				)
			case .argb:
				return gifski_add_frame_argb(
					pointer,
					UInt32(frameNumber),
					UInt32(width),
					UInt32(bytesPerRow),
					UInt32(height),
					&pixels,
					presentationTimestamp
				)
			case .rgb:
				return gifski_add_frame_rgb(
					pointer,
					UInt32(frameNumber),
					UInt32(width),
					UInt32(bytesPerRow),
					UInt32(height),
					&pixels,
					presentationTimestamp
				)
			}
		}
	}

	func finish() throws {
		guard !hasFinished else {
			throw Error.invalidState
		}

		hasFinished = true

		defer {
			unmanagedSelf.release()
		}

		try wrap {
			gifski_finish(pointer)
		}
	}
}

extension GifskiWrapper {
	enum Error: UInt32, LocalizedError {
		case nullArg = 1
		case invalidState
		case quant
		case gif
		case threadLost
		case notFound
		case permissionDenied
		case alreadyExists
		case invalidInput
		case timedOut
		case writeZero
		case interrupted
		case unexpectedEof
		case aborted
		case other

		var errorDescription: String? {
			switch self {
			case .nullArg:
				return "One of input arguments was NULL"
			case .invalidState:
				return "A one-time function was called twice, or functions were called in wrong order"
			case .quant:
				return "Internal error related to palette quantization"
			case .gif:
				return "Internal error related to GIF composing"
			case .threadLost:
				return "Internal error related (panic)"
			case .notFound:
				return "I/O error: File or directory not found"
			case .permissionDenied:
				return "I/O error: Permission denied"
			case .alreadyExists:
				return "I/O error: File already exists"
			case .invalidInput:
				return "Invalid arguments passed to function"
			case .timedOut, .writeZero, .interrupted, .unexpectedEof:
				return "Misc I/O error"
			case .aborted:
				return "Progress callback returned 0, writing aborted"
			case .other:
				return "Should not happen, file a bug: https://github.com/ImageOptim/gifski"
			}
		}
	}
}
