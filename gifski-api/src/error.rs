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

pub type CatResult<T> = Result<T, Error>;
