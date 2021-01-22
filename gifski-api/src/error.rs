use gif_dispose;
use imagequant;
use std::io;

quick_error! {
    #[derive(Debug)]
    pub enum Error {
        ThreadSend {
            display("thread aborted")
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
            display("I/O: {}", err)
        }
        PNG(msg: String) {
            display("{}", msg)
        }
        WrongSize(msg: String) {
            display("{}", msg)
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
    fn from(err: gif::EncodingError) -> Self {
        match err {
            gif::EncodingError::Io(err) => err.into(),
            other => Error::Gif(other),
        }
    }
}

impl<T> From<crossbeam_channel::SendError<T>> for Error {
    fn from(_: crossbeam_channel::SendError<T>) -> Self {
        Self::ThreadSend
    }
}

impl From<crossbeam_channel::RecvError> for Error {
    fn from(_: crossbeam_channel::RecvError) -> Self {
        Self::Aborted
    }
}
