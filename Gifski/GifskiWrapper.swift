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
            return "one of input arguments was NULL"
        case .invalidState:
            return "a one-time function was called twice, or functions were called in wrong order"
        case .quant:
            return "internal error related to palette quantization"
        case .gif:
            return "internal error related to gif composing"
        case .threadLost:
            return "internal error related to multithreading"
        case .notFound:
            return "I/O error: file or directory not found"
        case .permissionDenied:
            return "I/O error: permission denied"
        case .alreadyExists:
            return "I/O error: file already exists"
        case .invalidInput:
            return "invalid arguments passed to function"
        case .timedOut:
            return "misc I/O error"
        case .writeZero:
            return "misc I/O error"
        case .interrupted:
            return "misc I/O error"
        case .unexpectedEof:
            return "misc I/O error"
        case .aborted:
            return "progress callback returned 0, writing aborted"
        case .other:
            return "should not happen, file a bug"
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

    deinit {
        gifski_drop(pointer)
    }

    func setProgressCallback(context: UnsafeMutableRawPointer, cb: @escaping (@convention(c) (UnsafeMutableRawPointer?) -> Int32)) {
        gifski_set_progress_callback(pointer, cb, context)
    }

    func addFrameARGB(index: Int, image: CGImage, fps: Double) throws {
        let buffer = CFDataGetBytePtr(image.dataProvider!.data)
        try wrap {
            gifski_add_frame_rgb(
                pointer,
                UInt32(index),
                UInt32(image.width),
                UInt32(image.bytesPerRow),
                UInt32(image.height),
                buffer,
                UInt16(100 / fps)
            )
        }
    }

    func endAddingFrames() throws {
        try wrap { gifski_end_adding_frames(pointer) }
    }

    func write(path: String) throws {
        try wrap { gifski_write(pointer, path) }
    }

    private func wrap(_ fn: () -> GifskiError) throws {
        let result = fn()
        guard result == GIFSKI_OK else {
            throw GifskiWrapperError(rawValue: result.rawValue) ?? .other
        }
    }
}
