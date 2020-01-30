#![allow(deprecated)]

use gif_dispose;
use imagequant;
use std::io;

error_chain! {
    types {
        Error, ErrorKind, ResultExt, CatResult;
    }
    errors {
        ThreadSend {}
        Aborted {}
        Gifsicle {}
    }
    foreign_links {
        Io(io::Error);
        Quant(imagequant::liq_error);
        Pal(gif_dispose::Error);
    }
}
