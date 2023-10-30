use crate::WrongSizeError;
use std::num::TryFromIntError;
use std::io;
use quick_error::quick_error;

quick_error! {
    #[derive(Debug)]
    pub enum Error {
        /// Internal error
        ThreadSend {
            display("Internal error; unexpectedly aborted")
        }
        Aborted {
            display("aborted")
        }
        Gifsicle {
            display("gifsicle failure")
        }
        Gif(err: gif::EncodingError) {
            display("GIF encoding error: {}", err)
        }
        NoFrames {
            display("Found no usable frames to encode")
        }
        Io(err: io::Error) {
            from()
            from(_oom: std::collections::TryReserveError) -> (io::ErrorKind::OutOfMemory.into())
            display("I/O: {}", err)
        }
        PNG(msg: String) {
            display("{}", msg)
        }
        WrongSize(msg: String) {
            display("{}", msg)
            from(e: TryFromIntError) -> (e.to_string())
            from(_e: WrongSizeError) -> ("wrong size".to_string())
            from(e: resize::Error) -> (e.to_string())
        }
        Quant(liq: imagequant::liq_error) {
            from()
            display("pngquant error: {}", liq)
        }
        Pal(gif: gif_dispose::Error) {
            from()
            display("gif dispose error: {}", gif)
        }
    }
}

pub type CatResult<T, E = Error> = Result<T, E>;

impl From<gif::EncodingError> for Error {
    #[cold]
    fn from(err: gif::EncodingError) -> Self {
        match err {
            gif::EncodingError::Io(err) => err.into(),
            other => Error::Gif(other),
        }
    }
}

impl<T> From<crossbeam_channel::SendError<T>> for Error {
    #[cold]
    fn from(_: crossbeam_channel::SendError<T>) -> Self {
        Self::ThreadSend
    }
}

impl From<crossbeam_channel::RecvError> for Error {
    #[cold]
    fn from(_: crossbeam_channel::RecvError) -> Self {
        Self::Aborted
    }
}
