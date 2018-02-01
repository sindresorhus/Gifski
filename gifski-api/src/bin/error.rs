use gifski;
use std::io;
use std::num;
#[cfg(feature = "video")]
use ffmpeg;

#[cfg(not(feature = "video"))]
mod ffmpeg {
    pub use ::std::fmt::Error;
}


error_chain! {
    types {
        Error, ErrorKind, ResultExt, BinResult;
    }
    foreign_links {
        GifSki(gifski::Error);
        Video(ffmpeg::Error);
        Io(io::Error);
        Num(num::ParseIntError);
    }
}
