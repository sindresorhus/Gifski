//! How to use from C
//!
//! Please note that it is impossible to use this API in a single-threaded program.
//!   You must have at least two threads -- one for adding the frames, and another for writing.
//!
//!  ```c
//!  gifski *g = gifski_new(&settings);
//!
//!  // Call on decoder thread:
//!  gifski_add_frame_rgba(g, i, width, height, buffer, 5);
//!  gifski_end_adding_frames(g);
//!
//!  // Call on encoder thread:
//!  gifski_write(g, "file.gif");
//!  gifski_drop(g);
//!  ```
//!
//!  It's safe to call `gifski_drop()` after `gifski_write()`, because `gifski_write()` blocks until `gifski_end_adding_frames()` is called.
//!
//!  It's safe and efficient to call `gifski_add_frame_*` in a loop as fast as you can get frames,
//!  because it blocks and waits until previous frames are written.

use super::*;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::mem;
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

#[repr(C)]
#[derive(Copy, Clone)]
pub struct ARGB8 {
    pub a: u8,
    pub r: u8,
    pub g: u8,
    pub b: u8,
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
/// Delay is in 1/100ths of a second.
///
/// While you add frames, `gifski_write()` should be running already on another thread.
/// If `gifski_write()` is not running already, it may make `gifski_add_frame_*` block and wait for
/// write to start.
///
/// Call `gifski_end_adding_frames()` after you add all frames.
///
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
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
/// Delay is in 1/100ths of a second.
///
/// While you add frames, `gifski_write()` should be running already on another thread.
/// If `gifski_write()` is not running already, it may make `gifski_add_frame_*` block and wait for
/// write to start.
///
/// Call `gifski_end_adding_frames()` after you add all frames.
///
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
#[no_mangle]
pub extern "C" fn gifski_add_frame_rgba(handle: *mut GifskiHandle, index: u32, width: u32, height: u32, pixels: *const RGBA8, delay: u16) -> GifskiError {
    if pixels.is_null() {
        return GifskiError::NULL_ARG;
    }
    let pixels = unsafe {
        slice::from_raw_parts(pixels, width as usize * height as usize)
    };
    add_frame_rgba(handle, index, ImgVec::new(pixels.to_owned(), width as usize, height as usize), delay)
}

fn add_frame_rgba(handle: *mut GifskiHandle, index: u32, frame: ImgVec<RGBA8>, delay: u16) -> GifskiError {
    if handle.is_null() {
        return GifskiError::NULL_ARG;
    }
    let g = unsafe {handle.as_mut().unwrap()};
    if let Some(ref mut c) = g.collector {
        c.add_frame_rgba(index as usize, frame, delay).into()
    } else {
        GifskiError::INVALID_STATE
    }
}

/// Same as `gifski_add_frame_rgba`, except it expects components in ARGB order
///
/// Bytes per row must be multiple of 4 and greater or equal width×4.
#[no_mangle]
pub extern "C" fn gifski_add_frame_argb(handle: *mut GifskiHandle, index: u32, width: u32, bytes_per_row: u32, height: u32, pixels: *const ARGB8, delay: u16) -> GifskiError {
    if pixels.is_null() {
        return GifskiError::NULL_ARG;
    }
    let width = width as usize;
    let stride = bytes_per_row as usize / mem::size_of_val(unsafe{&*pixels});
    if stride < width {
        return GifskiError::INVALID_INPUT;
    }
    let pixels = unsafe {
        slice::from_raw_parts(pixels, stride * height as usize)
    };
    add_frame_rgba(handle, index, ImgVec::new(pixels.chunks(stride).flat_map(|r| r[0..width].iter().map(|p| RGBA8 {
        r: p.r,
        g: p.g,
        b: p.b,
        a: p.a,
    })).collect(), width as usize, height as usize), delay)
}

/// Same as `gifski_add_frame_rgba`, except it expects RGB components (3 bytes per pixel)
///
/// Bytes per row must be multiple of 3 and greater or equal width×3.
#[no_mangle]
pub extern "C" fn gifski_add_frame_rgb(handle: *mut GifskiHandle, index: u32, width: u32, bytes_per_row: u32, height: u32, pixels: *const RGB8, delay: u16) -> GifskiError {
    if pixels.is_null() {
        return GifskiError::NULL_ARG;
    }
    let width = width as usize;
    let stride = bytes_per_row as usize / mem::size_of_val(unsafe{&*pixels});
    if stride < width {
        return GifskiError::INVALID_INPUT;
    }
    let pixels = unsafe {
        slice::from_raw_parts(pixels, stride * height as usize)
    };
    add_frame_rgba(handle, index, ImgVec::new(pixels.chunks(stride).flat_map(|r| r[0..width].iter().map(|&p| p.into())).collect(), width as usize, height as usize), delay)
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
/// The callback is called once per frame.
/// It gets arbitrary pointer (`user_data`) as an argument. `user_data` can be `NULL`.
/// The callback must be thread-safe (it will be called from another thread).
///
/// The callback must return `1` to continue processing, or `0` to abort.
///
/// Must be called before `gifski_write()` to take effect.
#[no_mangle]
pub extern "C" fn gifski_set_progress_callback(handle: *mut GifskiHandle, cb: unsafe fn(*mut c_void) -> c_int, user_data: *mut c_void) {
    let g = unsafe {handle.as_mut().unwrap()};
    g.progress = Some(ProgressCallback::new(cb, user_data));
}

/// Start writing to the `destination` and keep waiting for more frames until `gifski_end_adding_frames()` is called.
///
/// This call will block until the entire file is written. You will need to add frames on another thread.
///
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
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

    let rgb: *const RGB8 = ptr::null();
    assert_eq!(3, mem::size_of_val(unsafe{&*rgb}));

    assert!(!g.is_null());
    assert_eq!(GifskiError::NULL_ARG, gifski_add_frame_rgba(g, 0, 1, 1, ptr::null(), 5));
    fn cb(_: *mut c_void) -> c_int {
        1
    }
    gifski_set_progress_callback(g, cb, ptr::null_mut());
    assert_eq!(GifskiError::OK, gifski_add_frame_rgba(g, 0, 1, 1, &RGBA::new(0,0,0,0), 5));
    assert_eq!(GifskiError::OK, gifski_add_frame_rgb(g, 1, 1, 3, 1, &RGB::new(0,0,0), 5));
    assert_eq!(GifskiError::OK, gifski_end_adding_frames(g));
    assert_eq!(GifskiError::INVALID_STATE, gifski_end_adding_frames(g));
    gifski_drop(g);
}
