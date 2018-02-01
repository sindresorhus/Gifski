use std::io;
use imagequant;
use gif_dispose;

error_chain! {
    types {
        Error, ErrorKind, ResultExt, CatResult;
    }
    errors {
        ThreadSend {}
        Aborted {}
    }
    foreign_links {
        Io(io::Error);
        Quant(imagequant::liq_error);
        Pal(gif_dispose::Error);
    }
}
