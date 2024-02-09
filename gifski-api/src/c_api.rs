#![allow(clippy::missing_safety_doc)]
//! How to use from C
//!
//! ```c
//! gifski *g = gifski_new(&(GifskiSettings){
//!     .quality = 90,
//! });
//! gifski_set_file_output(g, "file.gif");
//!
//! for(int i=0; i < frames; i++) {
//!      int res = gifski_add_frame_rgba(g, i, width, height, buffer, 5);
//!      if (res != GIFSKI_OK) break;
//! }
//! int res = gifski_finish(g);
//! if (res != GIFSKI_OK) return;
//! ```
//!
//! It's safe and efficient to call `gifski_add_frame_*` in a loop as fast as you can get frames,
//! because it blocks and waits until previous frames are written.
//!
//!
//! To cancel processing, make progress callback return 0 and call `gifski_finish()`. The write callback
//! may still be called between the cancellation and `gifski_finish()` returning.
//!
//! To build as a library:
//!
//! ```bash
//! cargo build --release --lib
//! ```
//!
//! it will create `target/release/libgifski.a` (static library)
//! and `target/release/libgifski.so`/`dylib` or `gifski.dll` (dynamic library)
//!
//! Static is recommended.
//!
//! To build for iOS:
//!
//! ```bash
//! rustup target add aarch64-apple-ios
//! cargo build --release --lib --target aarch64-apple-ios
//! ```
//!
//! it will build `target/aarch64-apple-ios/release/libgifski.a` (ignore the warning about cdylib).

use super::*;
use std::ffi::CStr;
use std::ffi::CString;
use std::fs;
use std::fs::File;
use std::io;
use std::mem;
use std::os::raw::{c_char, c_int, c_void};
use std::path::{Path, PathBuf};
use std::ptr;
use std::slice;
use std::sync::Arc;
use std::sync::Mutex;
use std::thread;
mod c_api_error;
use self::c_api_error::GifskiError;
use std::panic::catch_unwind;

/// Settings for creating a new encoder instance. See `gifski_new`
#[repr(C)]
#[derive(Copy, Clone)]
pub struct GifskiSettings {
    /// Resize to max this width if non-0.
    pub width: u32,
    /// Resize to max this height if width is non-0. Note that aspect ratio is not preserved.
    pub height: u32,
    /// 1-100, but useful range is 50-100. Recommended to set to 90.
    pub quality: u8,
    /// Lower quality, but faster encode.
    pub fast: bool,
    /// If negative, looping is disabled. The number of times the sequence is repeated. 0 to loop forever.
    pub repeat: i16,
}

#[repr(C)]
#[derive(Copy, Clone)]
pub struct ARGB8 {
    pub a: u8,
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

/// Opaque handle used in methods. Note that the handle pointer is actually `Arc<GifskiHandleInternal>`,
/// but `Arc::into_raw` is nice enough to point past the counter.
#[repr(C)]
pub struct GifskiHandle {
    _opaque: usize,
}
pub struct GifskiHandleInternal {
    writer: Mutex<Option<Writer>>,
    collector: Mutex<Option<Collector>>,
    progress: Mutex<Option<ProgressCallback>>,
    error_callback: Mutex<Option<Box<dyn Fn(String) + 'static + Sync + Send>>>,
    /// Bool set to true when the thread has been set up,
    /// prevents re-setting of the thread after finish()
    write_thread: Mutex<(bool, Option<thread::JoinHandle<GifskiError>>)>,
}

/// Call to start the process
///
/// See `gifski_add_frame_png_file` and `gifski_end_adding_frames`
///
/// Returns a handle for the other functions, or `NULL` on error (if the settings are invalid).
#[no_mangle]
pub unsafe extern "C" fn gifski_new(settings: *const GifskiSettings) -> *const GifskiHandle {
    let Some(settings) = settings.as_ref() else {
        return ptr::null_mut();
    };
    let s = Settings {
        width: if settings.width > 0 { Some(settings.width) } else { None },
        height: if settings.height > 0 { Some(settings.height) } else { None },
        quality: settings.quality,
        fast: settings.fast,
        repeat: if settings.repeat == -1 { Repeat::Finite(0) } else if settings.repeat == 0 { Repeat::Infinite } else { Repeat::Finite(settings.repeat as u16) },
    };

    if let Ok((collector, writer)) = new(s) {
        Arc::into_raw(Arc::new(GifskiHandleInternal {
            writer: Mutex::new(Some(writer)),
            write_thread: Mutex::new((false, None)),
            collector: Mutex::new(Some(collector)),
            progress: Mutex::new(None),
            error_callback: Mutex::new(None),
        })).cast::<GifskiHandle>()
    } else {
        ptr::null_mut()
    }
}

/// Quality 1-100 of temporal denoising. Lower values reduce motion. Defaults to `settings.quality`.
///
/// Only valid immediately after calling `gifski_new`, before any frames are added.
#[no_mangle]
pub unsafe extern "C" fn gifski_set_motion_quality(handle: *mut GifskiHandle, quality: u8) -> GifskiError {
    let Some(g) = borrow(handle) else { return GifskiError::NULL_ARG };

    if let Ok(Some(w)) = g.writer.lock().as_deref_mut() {
        #[allow(deprecated)]
        w.set_motion_quality(quality);
        GifskiError::OK
    } else {
        GifskiError::INVALID_STATE
    }
}

/// Quality 1-100 of gifsicle compression. Lower values add noise. Defaults to `settings.quality`.
/// Has no effect if the `gifsicle` feature hasn't been enabled.
/// Only valid immediately after calling `gifski_new`, before any frames are added.
#[no_mangle]
pub unsafe extern "C" fn gifski_set_lossy_quality(handle: *mut GifskiHandle, quality: u8) -> GifskiError {
    let Some(g) = borrow(handle) else { return GifskiError::NULL_ARG };

    if let Ok(Some(w)) = g.writer.lock().as_deref_mut() {
        #[allow(deprecated)]
        w.set_lossy_quality(quality);
        GifskiError::OK
    } else {
        GifskiError::INVALID_STATE
    }
}

/// If `true`, encoding will be significantly slower, but may look a bit better.
///
/// Only valid immediately after calling `gifski_new`, before any frames are added.
#[no_mangle]
pub unsafe extern "C" fn gifski_set_extra_effort(handle: *mut GifskiHandle, extra: bool) -> GifskiError {
    let Some(g) = borrow(handle) else { return GifskiError::NULL_ARG };

    if let Ok(Some(w)) = g.writer.lock().as_deref_mut() {
        #[allow(deprecated)]
        w.set_extra_effort(extra);
        GifskiError::OK
    } else {
        GifskiError::INVALID_STATE
    }
}

/// Adds a fixed color that will be kept in the palette at all times.
///
/// Only valid immediately after calling `gifski_new`, before any frames are added.
///
#[no_mangle]
pub unsafe extern "C" fn gifski_add_fixed_color(
    handle: *mut GifskiHandle,
    col_r: u8,
    col_g: u8,
    col_b: u8,
) -> GifskiError {
    let Some(g) = borrow(handle) else { return GifskiError::NULL_ARG };

    if let Ok(Some(w)) = g.writer.lock().as_deref_mut() {
        w.add_fixed_color(RGB8::new(col_r, col_g, col_b));
        GifskiError::OK
    } else {
        GifskiError::INVALID_STATE
    }
}

/// Adds a frame to the animation. This function is asynchronous.
///
/// File path must be valid UTF-8.
///
/// `frame_number` orders frames (consecutive numbers starting from 0).
/// You can add frames in any order, and they will be sorted by their `frame_number`.
///
/// Presentation timestamp (PTS) is time in seconds, since start of the file, when this frame is to be displayed.
/// For a 20fps video it could be `frame_number/20.0`.
/// Frames with duplicate or out-of-order PTS will be skipped.
///
/// The first frame should have PTS=0. If the first frame has PTS > 0, it'll be used as a delay after the last frame.
///
/// This function may block and wait until the frame is processed. Make sure to call `gifski_set_write_callback` or `gifski_set_file_output` first to avoid a deadlock.
///
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
#[no_mangle]
#[cfg(feature = "png")]
pub unsafe extern "C" fn gifski_add_frame_png_file(handle: *const GifskiHandle, frame_number: u32, file_path: *const c_char, presentation_timestamp: f64) -> GifskiError {
    if file_path.is_null() {
        return GifskiError::NULL_ARG;
    }
    let Some(g) = borrow(handle) else { return GifskiError::NULL_ARG };

    let path = if let Ok(s) = CStr::from_ptr(file_path).to_str() {
        PathBuf::from(s)
    } else {
        return GifskiError::INVALID_INPUT;
    };
    if let Ok(Some(c)) = g.collector.lock().as_deref_mut() {
        c.add_frame_png_file(frame_number as usize, path, presentation_timestamp).into()
    } else {
        g.print_error(format!("frame {frame_number} can't be added any more, because gifski_end_adding_frames has been called already"));
        GifskiError::INVALID_STATE
    }
}

/// Pixels is an array width×height×4 bytes large. The array is copied, so you can free/reuse it immediately.
///
/// Presentation timestamp (PTS) is time in seconds, since start of the file (at 0), when this frame is to be displayed.
/// For a 20fps video it could be `frame_number/20.0`.
/// Frames with duplicate or out-of-order PTS will be skipped.
///
/// The first frame should have PTS=0. If the first frame has PTS > 0, it'll be used as a delay after the last frame.
///
/// Colors are in sRGB, uncorrelated RGBA, with alpha byte last.
///
/// This function may block and wait until the frame is processed. Make sure to call `gifski_set_write_callback` or `gifski_set_file_output` first to avoid a deadlock.
///
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
#[no_mangle]
pub unsafe extern "C" fn gifski_add_frame_rgba(handle: *const GifskiHandle, frame_number: u32, width: u32, height: u32, pixels: *const RGBA8, presentation_timestamp: f64) -> GifskiError {
    if pixels.is_null() {
        return GifskiError::NULL_ARG;
    }
    if width == 0 || height == 0 || width > 0xFFFF || height > 0xFFFF {
        return GifskiError::INVALID_INPUT;
    }
    let width = width as usize;
    let height = height as usize;
    let pixels = slice::from_raw_parts(pixels, width * height);
    add_frame_rgba(handle, frame_number, Img::new(pixels.into(), width, height), presentation_timestamp)
}

/// Same as `gifski_add_frame_rgba`, but with bytes per row arg.
#[no_mangle]
pub unsafe extern "C" fn gifski_add_frame_rgba_stride(handle: *const GifskiHandle, frame_number: u32, width: u32, height: u32, bytes_per_row: u32, pixels: *const RGBA8, presentation_timestamp: f64) -> GifskiError {
    let (pixels, stride) = match pixels_slice(pixels, width, height, bytes_per_row) {
        Ok(v) => v,
        Err(err) => return err,
    };
    let img = ImgVec::new_stride(pixels.into(), width as _, height as _, stride);
    add_frame_rgba(handle, frame_number, img, presentation_timestamp)
}

unsafe fn pixels_slice<'a, T>(pixels: *const T, width: u32, height: u32, bytes_per_row: u32) -> Result<(&'a [T], usize), GifskiError> {
    if pixels.is_null() {
        return Err(GifskiError::NULL_ARG);
    }
    let stride = bytes_per_row as usize / mem::size_of::<T>();
    let width = width as usize;
    let height = height as usize;
    if stride < width || width == 0 || height == 0 || width > 0xFFFF || height > 0xFFFF {
        return Err(GifskiError::INVALID_INPUT);
    }
    let pixels = slice::from_raw_parts(pixels, stride * height + width - stride);
    Ok((pixels, stride))
}

fn add_frame_rgba(handle: *const GifskiHandle, frame_number: u32, frame: ImgVec<RGBA8>, presentation_timestamp: f64) -> GifskiError {
    let Some(g) = (unsafe { borrow(handle) }) else { return GifskiError::NULL_ARG };

    if let Ok(Some(c)) = g.collector.lock().as_deref_mut() {
        c.add_frame_rgba(frame_number as usize, frame, presentation_timestamp).into()
    } else {
        g.print_error(format!("frame {frame_number} can't be added any more, because gifski_end_adding_frames has been called already"));
        GifskiError::INVALID_STATE
    }
}

/// Same as `gifski_add_frame_rgba`, except it expects components in ARGB order.
///
/// Bytes per row must be multiple of 4 and greater or equal width×4.
///
/// Colors are in sRGB, uncorrelated ARGB, with alpha byte first.
///
/// `gifski_add_frame_rgba` is preferred over this function.
#[no_mangle]
pub unsafe extern "C" fn gifski_add_frame_argb(handle: *const GifskiHandle, frame_number: u32, width: u32, bytes_per_row: u32, height: u32, pixels: *const ARGB8, presentation_timestamp: f64) -> GifskiError {
    let (pixels, stride) = match pixels_slice(pixels, width, height, bytes_per_row) {
        Ok(v) => v,
        Err(err) => return err,
    };
    let width = width as usize;
    let height = height as usize;
    let img = ImgVec::new(pixels.chunks(stride).flat_map(|r| r[0..width].iter().map(|p| RGBA8 {
        r: p.r,
        g: p.g,
        b: p.b,
        a: p.a,
    })).collect(), width, height);
    add_frame_rgba(handle, frame_number, img, presentation_timestamp)
}

/// Same as `gifski_add_frame_rgba`, except it expects RGB components (3 bytes per pixel).
///
/// Bytes per row must be multiple of 3 and greater or equal width×3.
///
/// Colors are in sRGB, red byte first.

/// This function may block and wait until the frame is processed. Make sure to call `gifski_set_write_callback` first to avoid a deadlock.
///
/// `gifski_add_frame_rgba` is preferred over this function.
#[no_mangle]
pub unsafe extern "C" fn gifski_add_frame_rgb(handle: *const GifskiHandle, frame_number: u32, width: u32, bytes_per_row: u32, height: u32, pixels: *const RGB8, presentation_timestamp: f64) -> GifskiError {
    let (pixels, stride) = match pixels_slice(pixels, width, height, bytes_per_row) {
        Ok(v) => v,
        Err(err) => return err,
    };
    let width = width as usize;
    let height = height as usize;
    let img = ImgVec::new(pixels.chunks(stride).flat_map(|r| r[0..width].iter().map(|&p| p.alpha(255))).collect(), width, height);
    add_frame_rgba(handle, frame_number, img, presentation_timestamp)
}

/// Get a callback for frame processed, and abort processing if desired.
///
/// The callback is called once per input frame,
/// even if the encoder decides to skip some frames.
///
/// It gets arbitrary pointer (`user_data`) as an argument. `user_data` can be `NULL`.
///
/// The callback must return `1` to continue processing, or `0` to abort.
///
/// The callback must be thread-safe (it will be called from another thread).
/// It must remain valid at all times, until `gifski_finish` completes.
///
/// This function must be called before `gifski_set_file_output()` to take effect.
#[no_mangle]
pub unsafe extern "C" fn gifski_set_progress_callback(handle: *const GifskiHandle, cb: unsafe extern fn(*mut c_void) -> c_int, user_data: *mut c_void) -> GifskiError {
    let Some(g) = borrow(handle) else { return GifskiError::NULL_ARG };

    if g.write_thread.lock().map_or(true, |t| t.0) {
        g.print_error("tried to set progress callback after writing has already started".into());
        return GifskiError::INVALID_STATE;
    }
    match g.progress.lock() {
        Ok(mut progress) => {
            *progress = Some(ProgressCallback::new(cb, user_data));
            GifskiError::OK
        },
        Err(_) => GifskiError::THREAD_LOST,
    }
}

/// Get a callback when an error occurs.
/// This is intended mostly for logging and debugging, not for user interface.
///
/// The callback function has the following arguments:
/// * A `\0`-terminated C string in UTF-8 encoding. The string is only valid for the duration of the call. Make a copy if you need to keep it.
/// * An arbitrary pointer (`user_data`). `user_data` can be `NULL`.
///
/// The callback must be thread-safe (it will be called from another thread).
/// It must remain valid at all times, until `gifski_finish` completes.
///
/// If the callback is not set, errors will be printed to stderr.
///
/// This function must be called before `gifski_set_file_output()` to take effect.
#[no_mangle]
pub unsafe extern "C" fn gifski_set_error_message_callback(handle: *const GifskiHandle, cb: unsafe extern fn(*const c_char, *mut c_void), user_data: *mut c_void) -> GifskiError {
    let Some(g) = borrow(handle) else { return GifskiError::NULL_ARG };

    let user_data = SendableUserData(user_data);
    match g.error_callback.lock() {
        Ok(mut error_callback) => {
            *error_callback = Some(Box::new(move |mut s: String| {
                s.reserve_exact(1);
                s.push('\0');
                let cstring = CString::from_vec_with_nul(s.into_bytes()).unwrap_or_default();
                unsafe { cb(cstring.as_ptr(), user_data.clone().0) } // the clone is a no-op, only to force closure to own it
            }));
            GifskiError::OK
        },
        Err(_) => GifskiError::THREAD_LOST,
    }
}

#[derive(Clone)]
struct SendableUserData(*mut c_void);
unsafe impl Send for SendableUserData {}
unsafe impl Sync for SendableUserData {}

/// Start writing to the `destination`. This has to be called before any frames are added.
///
/// This call will not block.
///
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
#[no_mangle]
pub unsafe extern "C" fn gifski_set_file_output(handle: *const GifskiHandle, destination: *const c_char) -> GifskiError {
    let Some(g) = borrow(handle) else { return GifskiError::NULL_ARG };
    catch_unwind(move || {
        let (file, path) = match prepare_for_file_writing(g, destination) {
            Ok(res) => res,
            Err(err) => return err,
        };
        gifski_write_thread_start(g, file, Some(path)).err().unwrap_or(GifskiError::OK)
    })
    .map_err(move |e| g.print_panic(e)).unwrap_or(GifskiError::THREAD_LOST)
}


fn prepare_for_file_writing(g: &GifskiHandleInternal, destination: *const c_char) -> Result<(File, PathBuf), GifskiError> {
    if destination.is_null() {
        return Err(GifskiError::NULL_ARG);
    }
    let path = if let Ok(s) = unsafe { CStr::from_ptr(destination).to_str() } {
        Path::new(s)
    } else {
        return Err(GifskiError::INVALID_INPUT);
    };
    let t = g.write_thread.lock().map_err(|_| GifskiError::THREAD_LOST)?;
    if t.0 {
        g.print_error("tried to start writing for the second time, after it has already started".into());
        return Err(GifskiError::INVALID_STATE);
    }
    match File::create(path) {
        Ok(file) => Ok((file, path.into())),
        Err(err) => Err(err.kind().into()),
    }
}

struct CallbackWriter {
    cb: unsafe extern "C" fn(usize, *const u8, *mut c_void) -> c_int,
    user_data: *mut c_void,
}

unsafe impl Send for CallbackWriter {}

impl io::Write for CallbackWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        match unsafe { (self.cb)(buf.len(), buf.as_ptr(), self.user_data) } {
            0 => Ok(buf.len()),
            x => Err(GifskiError::from(x).into()),
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        match unsafe { (self.cb)(0, ptr::null(), self.user_data) } {
            0 => Ok(()),
            x => Err(GifskiError::from(x).into()),
        }
    }
}

/// Start writing via callback (any buffer, file, whatever you want). This has to be called before any frames are added.
/// This call will not block.
///
/// The callback function receives 3 arguments:
///  - size of the buffer to write, in bytes. IT MAY BE ZERO (when it's zero, either do nothing, or flush internal buffers if necessary).
///  - pointer to the buffer.
///  - context pointer to arbitrary user data, same as passed in to this function.
///
/// The callback should return 0 (`GIFSKI_OK`) on success, and non-zero on error.
///
/// The callback function must be thread-safe. It must remain valid at all times, until `gifski_finish` completes.
///
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
#[no_mangle]
pub unsafe extern "C" fn gifski_set_write_callback(handle: *const GifskiHandle, cb: Option<unsafe extern fn(usize, *const u8, *mut c_void) -> c_int>, user_data: *mut c_void) -> GifskiError {
    let Some(g) = borrow(handle) else { return GifskiError::NULL_ARG };
    catch_unwind(move || {
        let Some(cb) = cb else { return GifskiError::NULL_ARG };

        let writer = CallbackWriter { cb, user_data };
        gifski_write_thread_start(g, writer, None).err().unwrap_or(GifskiError::OK)
    })
    .map_err(move |e| g.print_panic(e)).unwrap_or(GifskiError::THREAD_LOST)
}

fn gifski_write_thread_start<W: 'static +  Write + Send>(g: &GifskiHandleInternal, file: W, path: Option<PathBuf>) -> Result<(), GifskiError> {
    let mut t = g.write_thread.lock().map_err(|_| GifskiError::THREAD_LOST)?;
    if t.0 {
        g.print_error("gifski_set_file_output/gifski_set_write_callback has been called already".into());
        return Err(GifskiError::INVALID_STATE);
    }
    let writer = g.writer.lock().map_err(|_| GifskiError::THREAD_LOST)?.take();
    let mut user_progress = g.progress.lock().map_err(|_| GifskiError::THREAD_LOST)?.take();
    let handle = thread::Builder::new().name("c-write".into()).spawn(move || {
        if let Some(writer) = writer {
            let progress = user_progress.as_mut().map(|m| m as &mut dyn ProgressReporter);
            match writer.write(file, progress.unwrap_or(&mut NoProgress {})).into() {
                res @ (GifskiError::OK | GifskiError::ALREADY_EXISTS) => res,
                err => {
                    if let Some(path) = path {
                        let _ = fs::remove_file(path); // clean up unfinished file
                    }
                    err
                },
            }
        } else {
            eprintln!("gifski_set_file_output/gifski_set_write_callback has been called already");
            GifskiError::INVALID_STATE
        }
    });
    match handle {
        Ok(handle) => {
            *t = (true, Some(handle));
            Ok(())
        },
        Err(_) => Err(GifskiError::THREAD_LOST),
    }
}

unsafe fn borrow<'a>(handle: *const GifskiHandle) -> Option<&'a GifskiHandleInternal> {
    let g = handle.cast::<GifskiHandleInternal>();
    g.as_ref()
}

/// The last step:
///  - stops accepting any more frames (`gifski_add_frame_*` calls are blocked)
///  - blocks and waits until all already-added frames have finished writing
///
/// Returns final status of write operations. Remember to check the return value!
///
/// Must always be called, otherwise it will leak memory.
/// After this call, the handle is freed and can't be used any more.
///
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
#[no_mangle]
pub unsafe extern "C" fn gifski_finish(g: *const GifskiHandle) -> GifskiError {
    if g.is_null() {
        return GifskiError::NULL_ARG;
    }
    let g = Arc::from_raw(g.cast::<GifskiHandleInternal>());
    catch_unwind(|| {
        match g.collector.lock() {
            // dropping of the collector (if any) completes writing
            Ok(mut lock) => *lock = None,
            Err(_) => {
                g.print_error("warning: collector thread crashed".into());
            },
        };

        let thread = match g.write_thread.lock() {
            Ok(mut writer) => writer.1.take(),
            Err(_) => return GifskiError::THREAD_LOST,
        };

        if let Some(thread) = thread {
            thread.join().map_err(|e| g.print_panic(e)).unwrap_or(GifskiError::THREAD_LOST)
        } else {
            g.print_error("warning: gifski_finish called before any output has been set".into());
            GifskiError::OK // this will become INVALID_STATE once sync write support is dropped
        }
    })
    .map_err(move |e| g.print_panic(e)).unwrap_or(GifskiError::THREAD_LOST)
}

impl GifskiHandleInternal {
    fn print_error(&self, mut err: String) {
        if let Ok(Some(cb)) = self.error_callback.lock().as_deref() {
            cb(err);
        } else {
            err.reserve_exact(1);
            err.push('\n');
            let _ = std::io::stderr().write_all(err.as_bytes());
        }
    }

    fn print_panic(&self, e: Box<dyn std::any::Any + Send>) {
        let msg = e.downcast_ref::<String>().map(|s| s.as_str())
            .or_else(|| e.downcast_ref::<&str>().copied()).unwrap_or("unknown panic");
        self.print_error(format!("writer crashed (this is a bug): {msg}"));
    }
}

#[test]
fn c_cb() {
    let g = unsafe {
        gifski_new(&GifskiSettings {
            width: 1,
            height: 1,
            quality: 100,
            fast: false,
            repeat: -1,
        })
    };
    assert!(!g.is_null());
    let mut write_called = false;
    unsafe extern "C" fn cb(_s: usize, _buf: *const u8, user_data: *mut c_void) -> c_int {
        let write_called = user_data.cast::<bool>();
        *write_called = true;
        0
    }
    let mut progress_called = 0u32;
    unsafe extern "C" fn pcb(user_data: *mut c_void) -> c_int {
        let progress_called = user_data.cast::<u32>();
        *progress_called += 1;
        1
    }
    unsafe {
        assert_eq!(GifskiError::OK, gifski_set_progress_callback(g, pcb, ptr::addr_of_mut!(progress_called).cast()));
        assert_eq!(GifskiError::OK, gifski_set_write_callback(g, Some(cb), ptr::addr_of_mut!(write_called).cast()));
        assert_eq!(GifskiError::INVALID_STATE, gifski_set_progress_callback(g, pcb, ptr::addr_of_mut!(progress_called).cast()));
        assert_eq!(GifskiError::OK, gifski_add_frame_rgb(g, 0, 1, 3, 1, &RGB::new(0,0,0), 3.));
        assert_eq!(GifskiError::OK, gifski_add_frame_rgb(g, 0, 1, 3, 1, &RGB::new(0,0,0), 10.));
        assert_eq!(GifskiError::OK, gifski_finish(g));
    }
    assert!(write_called);
    assert_eq!(2, progress_called);
}

#[test]
fn progress_abort() {
    let g = unsafe {
        gifski_new(&GifskiSettings {
            width: 1,
            height: 1,
            quality: 100,
            fast: false,
            repeat: -1,
        })
    };
    assert!(!g.is_null());
    unsafe extern "C" fn cb(_size: usize, _buf: *const u8, _user_data: *mut c_void) -> c_int {
        0
    }
    unsafe extern "C" fn pcb(_user_data: *mut c_void) -> c_int {
        0
    }
    unsafe {
        assert_eq!(GifskiError::OK, gifski_set_progress_callback(g, pcb, ptr::null_mut()));
        assert_eq!(GifskiError::OK, gifski_set_write_callback(g, Some(cb), ptr::null_mut()));
        assert_eq!(GifskiError::OK, gifski_add_frame_rgb(g, 0, 1, 3, 1, &RGB::new(0,0,0), 3.));
        assert_eq!(GifskiError::OK, gifski_add_frame_rgb(g, 0, 1, 3, 1, &RGB::new(0,0,0), 10.));
        assert_eq!(GifskiError::ABORTED, gifski_finish(g));
    }
}

#[test]
fn cant_write_after_finish() {
    let g = unsafe { gifski_new(&GifskiSettings {
        width: 1, height: 1,
        quality: 100,
        fast: false,
        repeat: -1,
    })};
    assert!(!g.is_null());
    unsafe extern "C" fn cb(_s: usize, _buf: *const u8, u1: *mut c_void) -> c_int {
        assert_eq!(u1 as usize, 1);
        0
    }
    unsafe {
        assert_eq!(GifskiError::OK, gifski_set_write_callback(g, Some(cb), 1 as _));
        assert_eq!(GifskiError::INVALID_STATE, gifski_finish(g));
    }
}

#[test]
fn c_write_failure_propagated() {
    let g = unsafe { gifski_new(&GifskiSettings {
        width: 1, height: 1,
        quality: 100,
        fast: false,
        repeat: -1,
    })};
    assert!(!g.is_null());
    unsafe extern fn cb(_s: usize, _buf: *const u8, _user: *mut c_void) -> c_int {
        GifskiError::WRITE_ZERO as c_int
    }
    unsafe {
        assert_eq!(GifskiError::OK, gifski_set_write_callback(g, Some(cb), ptr::null_mut()));
        assert_eq!(GifskiError::OK, gifski_add_frame_rgb(g, 0, 1, 3, 1, &RGB::new(0,0,0), 5.0));
        assert_eq!(GifskiError::WRITE_ZERO, gifski_finish(g));
    }
}

#[test]
fn test_error_callback() {
    let g = unsafe { gifski_new(&GifskiSettings {
        width: 1, height: 1,
        quality: 100,
        fast: false,
        repeat: -1,
    })};
    assert!(!g.is_null());
    unsafe extern "C" fn cb(_s: usize, _buf: *const u8, u1: *mut c_void) -> c_int {
        assert_eq!(u1 as usize, 1);
        0
    }
    unsafe extern "C" fn errcb(msg: *const c_char, user_data: *mut c_void) {
        let callback_msg = user_data.cast::<Option<String>>();
        *callback_msg = Some(CStr::from_ptr(msg).to_str().unwrap().to_string());
    }
    let mut callback_msg: Option<String> = None;
    unsafe {
        assert_eq!(GifskiError::OK, gifski_set_error_message_callback(g, errcb, std::ptr::addr_of_mut!(callback_msg) as _));
        assert_eq!(GifskiError::OK, gifski_set_write_callback(g, Some(cb), 1 as _));
        assert_eq!(GifskiError::INVALID_STATE, gifski_set_write_callback(g, Some(cb), 1 as _));
        assert_eq!(GifskiError::INVALID_STATE, gifski_finish(g));
        assert_eq!("gifski_set_file_output/gifski_set_write_callback has been called already", callback_msg.unwrap());
    }
}

#[test]
fn cant_write_twice() {
    let g = unsafe { gifski_new(&GifskiSettings {
        width: 1, height: 1,
        quality: 100,
        fast: false,
        repeat: -1,
    })};
    assert!(!g.is_null());
    unsafe extern "C" fn cb(_s: usize, _buf: *const u8, _user: *mut c_void) -> c_int {
        GifskiError::WRITE_ZERO as c_int
    }
    unsafe {
        assert_eq!(GifskiError::OK, gifski_set_write_callback(g, Some(cb), ptr::null_mut()));
        assert_eq!(GifskiError::INVALID_STATE, gifski_set_write_callback(g, Some(cb), ptr::null_mut()));
    }
}

#[test]
fn c_incomplete() {
    let g = unsafe { gifski_new(&GifskiSettings {
        width: 0, height: 0,
        quality: 100,
        fast: true,
        repeat: 0,
    })};

    let rgb: *const RGB8 = ptr::null();
    assert_eq!(3, mem::size_of_val(unsafe { &*rgb }));

    assert!(!g.is_null());
    unsafe {
        assert_eq!(GifskiError::NULL_ARG, gifski_add_frame_rgba(g, 0, 1, 1, ptr::null(), 5.0));
    }
    extern "C" fn cb(_: *mut c_void) -> c_int {
        1
    }
    unsafe {
        gifski_set_progress_callback(g, cb, ptr::null_mut());
        assert_eq!(GifskiError::OK, gifski_add_frame_rgba(g, 0, 1, 1, &RGBA8::new(0, 0, 0, 0), 5.0));
        assert_eq!(GifskiError::OK, gifski_add_frame_rgb(g, 1, 1, 3, 1, &RGB::new(0, 0, 0), 5.0));
        assert_eq!(GifskiError::OK, gifski_finish(g));
    }
}
