import Foundation

enum GifskiWrapperError: UInt32, LocalizedError {
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
			return "Internal error related to multithreading"
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

final class GifskiWrapper {
	private let pointer: OpaquePointer

	init?(settings: GifskiSettings) {
		var settings = settings
		guard let pointer = gifski_new(&settings) else {
			return nil
		}
		self.pointer = pointer
	}

	func setProgressCallback(context: UnsafeMutableRawPointer, cb: @escaping (@convention(c) (UnsafeMutableRawPointer?) -> Int32)) {
		gifski_set_progress_callback(pointer, cb, context)
	}

	// swiftlint:disable:next function_parameter_count
	func addFrameARGB(index: UInt32, width: UInt32, bytesPerRow: UInt32, height: UInt32, pixels: UnsafePointer<UInt8>, delay: UInt16) throws {
		try wrap {
			gifski_add_frame_argb(pointer, index, width, bytesPerRow, height, pixels, delay)
		}
	}

	func finish() throws {
		try wrap { gifski_finish(pointer) }
	}

	func setFileOutput(path: String) throws {
		try wrap { gifski_set_file_output(pointer, path) }
	}

	private func wrap(_ fn: () -> GifskiError) throws {
		let result = fn()
		guard result == GIFSKI_OK else {
			throw GifskiWrapperError(rawValue: result.rawValue) ?? .other
		}
	}
}
