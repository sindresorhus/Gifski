//! How to use from C
//!
//! ```c
//! gifski *g = gifski_new(&settings);
//!
//! // Call on decoder thread:
//! gifski_add_frame_rgba(g, i, width, height, buffer, 5);
//! gifski_end_adding_frames(g);
//!
//! // Call on encoder thread:
//! gifski_write(g, "file.gif");
//! gifski_drop(g);
//! ```

use super::*;
use std::os::raw::{c_char, c_int};
use std::ptr;
use std::slice;
use std::fs::File;
use std::ffi::CStr;
use std::path::{PathBuf, Path};

/// Settings for creating a new encoder instance. See `gifski_new`
#[repr(C)]
#[derive(Copy, Clone)]
pub struct GifskiSettings {
    /// Resize to max this width if non-0
    pub width: u32,
    /// Resize to max this height if width is non-0. Note that aspect ratio is not preserved.
    pub height: u32,
    /// 1-100, but useful range is 50-100. Recommended to set to 100.
    pub quality: u8,
    /// If true, looping is disabled. Recommended false (looping on).
    pub once: bool,
    /// Lower quality, but faster encode.
    pub fast: bool,
}

/// Opaque handle used in methods
pub struct GifskiHandle {
    writer: Option<Writer>,
    collector: Option<Collector>,
    progress: Option<ProgressCallback>,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
#[allow(non_camel_case_types)]
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

impl From<CatResult<()>> for GifskiError {
    fn from(res: CatResult<()>) -> Self {
        use error::ErrorKind::*;
        use std::io::ErrorKind as EK;
        match res {
            Ok(_) => GifskiError::OK,
            Err(err) => match *err.kind() {
                Quant(_) => GifskiError::QUANT,
                Pal(_) => GifskiError::GIF,
                ThreadSend => GifskiError::THREAD_LOST,
                Io(ref err) => match err.kind() {
                    EK::NotFound => GifskiError::NOT_FOUND,
                    EK::PermissionDenied => GifskiError::PERMISSION_DENIED,
                    EK::AlreadyExists => GifskiError::ALREADY_EXISTS,
                    EK::InvalidInput | EK::InvalidData => GifskiError::INVALID_INPUT,
                    EK::TimedOut => GifskiError::TIMED_OUT,
                    EK::WriteZero => GifskiError::WRITE_ZERO,
                    EK::Interrupted => GifskiError::INTERRUPTED,
                    EK::UnexpectedEof => GifskiError::UNEXPECTED_EOF,
                    _ => GifskiError::OTHER,
                },
                _ => GifskiError::OTHER,
            },
        }
    }
}

/// Call to start the process
///
/// See `gifski_add_frame_png_file` and `gifski_end_adding_frames`
#[no_mangle]
pub extern "C" fn gifski_new(settings: *const GifskiSettings) -> *mut GifskiHandle {
    let settings = unsafe {if let Some(s) = settings.as_ref() {s} else {
        return ptr::null_mut();
    }};
    let s = Settings {
        width: if settings.width > 0 {Some(settings.width)} else {None},
        height: if settings.height > 0 {Some(settings.height)} else {None},
        quality: settings.quality,
        once: settings.once,
        fast: settings.fast,
    };

    if let Ok((collector, writer)) = new(s) {
        Box::into_raw(Box::new(GifskiHandle {
            writer: Some(writer),
            collector: Some(collector),
            progress: None,
        }))
    } else {
        ptr::null_mut()
    }
}

/// File path must be valid UTF-8. This function is asynchronous.
///
/// Delay is in 1/100ths of a second
///
/// Call `gifski_end_adding_frames()` after you add all frames. See also `gifski_write()`
#[no_mangle]
pub extern "C" fn gifski_add_frame_png_file(handle: *mut GifskiHandle, index: u32, file_path: *const c_char, delay: u16) -> GifskiError {
    if file_path.is_null() {
        return GifskiError::NULL_ARG;
    }
    let g = unsafe {handle.as_mut().unwrap()};
    let path = PathBuf::from(unsafe {
        CStr::from_ptr(file_path).to_str().unwrap()
    });
    if let Some(ref mut c) = g.collector {
        c.add_frame_png_file(index as usize, path, delay).into()
    } else {
        GifskiError::INVALID_STATE
    }
}

/// Pixels is an array width×height×4 bytes large. The array is copied, so you can free/reuse it immediately.
///
/// Delay is in 1/100ths of a second
///
/// The call may block and wait until the encoder thread needs more frames.
///
/// Call `gifski_end_adding_frames()` after you add all frames. See also `gifski_write()`
#[no_mangle]
pub extern "C" fn gifski_add_frame_rgba(handle: *mut GifskiHandle, index: u32, width: u32, height: u32, pixels: *const RGBA8, delay: u16) -> GifskiError {
    if handle.is_null() || pixels.is_null() {
        return GifskiError::NULL_ARG;
    }
    let g = unsafe {handle.as_mut().unwrap()};
    if let Some(ref mut c) = g.collector {
        let px = unsafe {
            slice::from_raw_parts(pixels, width as usize * height as usize)
        };
        c.add_frame_rgba(index as usize, ImgVec::new(px.to_owned(), width as usize, height as usize), delay).into()
    } else {
        GifskiError::INVALID_STATE
    }
}

/// You must call it at some point (after all frames are set), otherwise `gifski_write()` will never end!
#[no_mangle]
pub extern "C" fn gifski_end_adding_frames(handle: *mut GifskiHandle) -> GifskiError {
    let g = unsafe {handle.as_mut().unwrap()};
    match g.collector.take() {
        Some(_) => GifskiError::OK,
        None => GifskiError::INVALID_STATE,
    }
}

/// Get a callback for frame processed, and abort processing if desired.
///
/// The callback is called once per frame with `NULL`, and then once with non-null message on end.
///
/// The callback must return `1` to continue processing, or `0` to abort.
///
/// Must be called before `gifski_write()`
#[no_mangle]
pub extern "C" fn gifski_set_progress_callback(handle: *mut GifskiHandle, cb: unsafe fn(*const i8) -> c_int) {
    let g = unsafe {handle.as_mut().unwrap()};
    g.progress = Some(ProgressCallback::new(cb));
}

/// Write frames to `destination` and keep waiting for more frames until `gifski_end_adding_frames` is called.
#[no_mangle]
pub extern "C" fn gifski_write(handle: *mut GifskiHandle, destination: *const c_char) -> GifskiError {
    if destination.is_null() {
        return GifskiError::NULL_ARG;
    }
    let g = unsafe {handle.as_mut().unwrap()};
    let path = Path::new(unsafe {
        CStr::from_ptr(destination).to_str().unwrap()
    });
    if let Ok(file) = File::create(path) {
        if let Some(writer) = g.writer.take() {
            let mut progress: &mut ProgressReporter = &mut NoProgress {};
            if let Some(cb) = g.progress.as_mut() {
                progress = cb;
            }
            return writer.write(file, progress).into();
        }
    }
    GifskiError::INVALID_STATE
}

/// Call to free all memory
#[no_mangle]
pub extern "C" fn gifski_drop(g: *mut GifskiHandle) {
    if !g.is_null() {
        unsafe {
            Box::from_raw(g);
        }
    }
}

#[test]
fn c() {
    let g = gifski_new(&GifskiSettings {
        width: 0, height: 0,
        quality: 100,
        once: false,
        fast: true,
    });
    assert!(!g.is_null());
    assert_eq!(GifskiError::NULL_ARG, gifski_add_frame_rgba(g, 0, 1, 1, ptr::null(), 5));
    fn cb(_m: *const i8) -> c_int {
        1
    }
    gifski_set_progress_callback(g, cb);
    assert_eq!(GifskiError::OK, gifski_add_frame_rgba(g, 0, 1, 1, &RGBA::new(0,0,0,0), 5));
    assert_eq!(GifskiError::OK, gifski_end_adding_frames(g));
    assert_eq!(GifskiError::INVALID_STATE, gifski_end_adding_frames(g));
    gifski_drop(g);
}
