use crate::CatResult;
use std::fmt;
use std::io;
use std::os::raw::c_int;

#[repr(C)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
#[allow(non_camel_case_types)]
#[allow(clippy::upper_case_acronyms)]
pub enum GifskiError {
    OK = 0,
    NULL_ARG,
    INVALID_STATE,
    QUANT,
    GIF,
    THREAD_LOST,
    NOT_FOUND,
    PERMISSION_DENIED,
    ALREADY_EXISTS,
    INVALID_INPUT,
    TIMED_OUT,
    WRITE_ZERO,
    INTERRUPTED,
    UNEXPECTED_EOF,
    ABORTED,
    OTHER,
}

impl From<GifskiError> for io::Error {
    #[cold]
    fn from(g: GifskiError) -> Self {
        use std::io::ErrorKind as EK;
        use GifskiError::*;
        match g {
            OK => panic!("wrong err code"),
            NOT_FOUND => EK::NotFound,
            PERMISSION_DENIED => EK::PermissionDenied,
            ALREADY_EXISTS => EK::AlreadyExists,
            INVALID_INPUT => EK::InvalidInput,
            TIMED_OUT => EK::TimedOut,
            WRITE_ZERO => EK::WriteZero,
            INTERRUPTED => EK::Interrupted,
            UNEXPECTED_EOF => EK::UnexpectedEof,
            _ => return io::Error::new(EK::Other, g),
        }.into()
    }
}

impl From<c_int> for GifskiError {
    #[cold]
    fn from(res: c_int) -> Self {
        use GifskiError::*;
        match res {
            x if x == OK as c_int => OK,
            x if x == NULL_ARG as c_int => NULL_ARG,
            x if x == INVALID_STATE as c_int => INVALID_STATE,
            x if x == QUANT as c_int => QUANT,
            x if x == GIF as c_int => GIF,
            x if x == THREAD_LOST as c_int => THREAD_LOST,
            x if x == NOT_FOUND as c_int => NOT_FOUND,
            x if x == PERMISSION_DENIED as c_int => PERMISSION_DENIED,
            x if x == ALREADY_EXISTS as c_int => ALREADY_EXISTS,
            x if x == INVALID_INPUT as c_int => INVALID_INPUT,
            x if x == TIMED_OUT as c_int => TIMED_OUT,
            x if x == WRITE_ZERO as c_int => WRITE_ZERO,
            x if x == INTERRUPTED as c_int => INTERRUPTED,
            x if x == UNEXPECTED_EOF as c_int => UNEXPECTED_EOF,
            x if x == ABORTED as c_int => ABORTED,
            _ => OTHER,
        }
    }
}

impl From<CatResult<()>> for GifskiError {
    #[cold]
    fn from(res: CatResult<()>) -> Self {
        use crate::error::Error::*;
        match res {
            Ok(()) => GifskiError::OK,
            Err(err) => match err {
                Quant(_) => GifskiError::QUANT,
                Pal(_) => GifskiError::GIF,
                ThreadSend => GifskiError::THREAD_LOST,
                Io(ref err) => err.kind().into(),
                Aborted => GifskiError::ABORTED,
                Gifsicle | Gif(_) => GifskiError::GIF,
                NoFrames => GifskiError::INVALID_STATE,
                WrongSize(_) => GifskiError::INVALID_INPUT,
                PNG(_) => GifskiError::OTHER,
            },
        }
    }
}

impl From<io::ErrorKind> for GifskiError {
    #[cold]
    fn from(res: io::ErrorKind) -> Self {
        use std::io::ErrorKind as EK;
        match res {
            EK::NotFound => GifskiError::NOT_FOUND,
            EK::PermissionDenied => GifskiError::PERMISSION_DENIED,
            EK::AlreadyExists => GifskiError::ALREADY_EXISTS,
            EK::InvalidInput | EK::InvalidData => GifskiError::INVALID_INPUT,
            EK::TimedOut => GifskiError::TIMED_OUT,
            EK::WriteZero => GifskiError::WRITE_ZERO,
            EK::Interrupted => GifskiError::INTERRUPTED,
            EK::UnexpectedEof => GifskiError::UNEXPECTED_EOF,
            _ => GifskiError::OTHER,
        }
    }
}

impl std::error::Error for GifskiError {}

impl fmt::Display for GifskiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Debug::fmt(self, f)
    }
}
