import Foundation

enum GifskiWrapperError: UInt32, Error {
    /** one of input arguments was NULL */
    case nullArg = 1
    /** a one-time function was called twice, or functions were called in wrong order */
    case invalidState
    /** internal error related to palette quantization */
    case quant
    /** internal error related to gif composing */
    case gif
    /** internal error related to multithreading */
    case threadLost
    /** I/O error: file or directory not found */
    case notFound
    /** I/O error: permission denied */
    case permissionDenied
    /** I/O error: file already exists */
    case alreadyExists
    /** invalid arguments passed to function */
    case invalidInput
    /** misc I/O error */
    case timedOut
    /** misc I/O error */
    case writeZero
    /** misc I/O error */
    case interrupted
    /** misc I/O error */
    case unexpectedEof
    /** progress callback returned 0, writing aborted */
    case aborted
    /** should not happen, file a bug */
    case other
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
