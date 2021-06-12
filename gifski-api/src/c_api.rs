#![allow(clippy::missing_safety_doc)]
//! How to use from C
//!
//! ```c
//! gifski *g = gifski_new(&(GifskiSettings){});
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
use self::c_api_error::*;

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
    let settings = if let Some(s) = settings.as_ref() {s} else {
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
        })) as *const GifskiHandle
    } else {
        ptr::null_mut()
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
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
#[no_mangle]
pub unsafe extern "C" fn gifski_add_frame_png_file(handle: *const GifskiHandle, frame_number: u32, file_path: *const c_char, presentation_timestamp: f64) -> GifskiError {
    if file_path.is_null() {
        return GifskiError::NULL_ARG;
    }
    let g = match borrow(handle) {
        Some(g) => g,
        None => return GifskiError::NULL_ARG,
    };
    let path = if let Ok(s) = CStr::from_ptr(file_path).to_str() {
        PathBuf::from(s)
    } else {
        return GifskiError::INVALID_INPUT;
    };
    if let Some(ref mut c) = *g.collector.lock().unwrap() {
        c.add_frame_png_file(frame_number as usize, path, presentation_timestamp).into()
    } else {
        eprintln!("frames can't be added any more, because gifski_end_adding_frames has been called already");
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
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
#[no_mangle]
pub unsafe extern "C" fn gifski_add_frame_rgba(handle: *const GifskiHandle, frame_number: u32, width: u32, height: u32, pixels: *const RGBA8, presentation_timestamp: f64) -> GifskiError {
    if pixels.is_null() {
        return GifskiError::NULL_ARG;
    }
    if width < 1 || height < 1 || width > 0xFFFF || height > 0xFFFF {
        return GifskiError::INVALID_INPUT;
    }
    let pixels = slice::from_raw_parts(pixels, width as usize * height as usize);
    add_frame_rgba(handle, frame_number, Img::new(pixels.into(), width as usize, height as usize), presentation_timestamp)
}

/// Same as `gifski_add_frame_rgba`, but with bytes per row arg.
#[no_mangle]
pub unsafe extern "C" fn gifski_add_frame_rgba_stride(handle: *const GifskiHandle, frame_number: u32, width: u32, height: u32, bytes_per_row: u32, pixels: *const RGBA8, presentation_timestamp: f64) -> GifskiError {
    if pixels.is_null() {
        return GifskiError::NULL_ARG;
    }
    let stride = bytes_per_row as usize / mem::size_of_val(&*pixels);
    let width = width as usize;
    let height = height as usize;
    if stride < width || height < 1 {
        return GifskiError::INVALID_INPUT;
    }
    let pixels = slice::from_raw_parts(pixels, stride * height + width - stride);
    let img = Img::new_stride(pixels.into(), width, height, stride);
    add_frame_rgba(handle, frame_number, img, presentation_timestamp)
}

fn add_frame_rgba(handle: *const GifskiHandle, frame_number: u32, frame: Img<Cow<[RGBA8]>>, presentation_timestamp: f64) -> GifskiError {
    let g = match unsafe { borrow(handle) } {
        Some(g) => g,
        None => return GifskiError::NULL_ARG,
    };
    if let Some(ref mut c) = *g.collector.lock().unwrap() {
        c.add_frame_rgba_cow(frame_number as usize, frame, presentation_timestamp).into()
    } else {
        eprintln!("frames can't be added any more, because gifski_end_adding_frames has been called already");
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
    if pixels.is_null() {
        return GifskiError::NULL_ARG;
    }
    let width = width as usize;
    let stride = bytes_per_row as usize / mem::size_of_val(&*pixels);
    if stride < width {
        return GifskiError::INVALID_INPUT;
    }
    let pixels = slice::from_raw_parts(pixels, stride * height as usize);
    let img = ImgVec::new(pixels.chunks(stride).flat_map(|r| r[0..width].iter().map(|p| RGBA8 {
        r: p.r,
        g: p.g,
        b: p.b,
        a: p.a,
    })).collect(), width as usize, height as usize);
    add_frame_rgba(handle, frame_number, img.into(), presentation_timestamp)
}

/// Same as `gifski_add_frame_rgba`, except it expects RGB components (3 bytes per pixel).
///
/// Bytes per row must be multiple of 3 and greater or equal width×3.
///
/// Colors are in sRGB, red byte first.
///
/// `gifski_add_frame_rgba` is preferred over this function.
#[no_mangle]
pub unsafe extern "C" fn gifski_add_frame_rgb(handle: *const GifskiHandle, frame_number: u32, width: u32, bytes_per_row: u32, height: u32, pixels: *const RGB8, presentation_timestamp: f64) -> GifskiError {
    if pixels.is_null() {
        return GifskiError::NULL_ARG;
    }
    let width = width as usize;
    let stride = bytes_per_row as usize / mem::size_of_val(&*pixels);
    if stride < width {
        return GifskiError::INVALID_INPUT;
    }
    let pixels = slice::from_raw_parts(pixels, stride * height as usize);
    let img = ImgVec::new(pixels.chunks(stride).flat_map(|r| r[0..width].iter().map(|&p| p.alpha(255))).collect(), width as usize, height as usize);
    add_frame_rgba(handle, frame_number, img.into(), presentation_timestamp)
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
    let g = match borrow(handle) {
        Some(g) => g,
        None => return GifskiError::NULL_ARG,
    };
    let t = g.write_thread.lock().unwrap();
    if t.0 {
        eprintln!("tried to set progress callback after writing has already started");
        return GifskiError::INVALID_STATE;
    }
    *g.progress.lock().unwrap() = Some(ProgressCallback::new(cb, user_data));
    GifskiError::OK
}

/// Start writing to the `destination`. This has to be called before any frames are added.
///
/// This call will not block.
///
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
#[no_mangle]
pub unsafe extern "C" fn gifski_set_file_output(handle: *const GifskiHandle, destination: *const c_char) -> GifskiError {
    let g = match borrow(handle) {
        Some(g) => g,
        None => return GifskiError::NULL_ARG,
    };
    let (file, path) = match prepare_for_file_writing(g, destination) {
        Ok(res) => res,
        Err(err) => return err,
    };
    gifski_write_thread_start(g, file, Some(path))
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
    let t = g.write_thread.lock().unwrap();
    if t.0 {
        eprintln!("tried to start writing for the second time, after it has already started");
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
///  - context pointer to arbitary user data, same as passed in to this function.
///
/// The callback should return 0 (`GIFSKI_OK`) on success, and non-zero on error.
///
/// The callback function must be thread-safe. It must remain valid at all times, until `gifski_finish` completes.
///
/// Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
#[no_mangle]
pub unsafe extern "C" fn gifski_set_write_callback(handle: *const GifskiHandle, cb: Option<unsafe extern fn(usize, *const u8, *mut c_void) -> c_int>, user_data: *mut c_void) -> GifskiError {
    let g = match borrow(handle) {
        Some(g) => g,
        None => return GifskiError::NULL_ARG,
    };
    let cb = match cb {
        Some(cb) => cb,
        None => return GifskiError::NULL_ARG,
    };
    let writer = CallbackWriter { cb, user_data };
    gifski_write_thread_start(g, writer, None)
}

fn gifski_write_thread_start<W: 'static +  Write + Send>(g: &GifskiHandleInternal, file: W, path: Option<PathBuf>) -> GifskiError {
    let mut t = g.write_thread.lock().unwrap();
    if t.0 {
        eprintln!("gifski_set_file_output/gifski_set_write_callback has been called already");
        return GifskiError::INVALID_STATE;
    }
    let writer = g.writer.lock().unwrap().take();
    let mut user_progress = g.progress.lock().unwrap().take();
    let handle = thread::Builder::new().name("c-write".into()).spawn(move || {
        if let Some(writer) = writer {
            let mut progress: &mut dyn ProgressReporter = &mut NoProgress {};
            if let Some(cb) = &mut user_progress {
                progress = &mut *cb;
            }
            match writer.write(file, progress).into() {
                res @ GifskiError::OK |
                res @ GifskiError::ALREADY_EXISTS => res,
                err => {
                    if let Some(path) = path {
                        let _ = fs::remove_file(path); // clean up unfinished file
                    }
                    err
                },
            }
        } else {
            eprintln!("gifski_set_file_output or gifski_write_* has been called once already");
            GifskiError::INVALID_STATE
        }
    });
    match handle {
        Ok(handle) => {
            *t = (true, Some(handle));
            GifskiError::OK
        },
        Err(_) => GifskiError::THREAD_LOST,
    }
}

unsafe fn borrow<'a>(handle: *const GifskiHandle) -> Option<&'a GifskiHandleInternal> {
    let g = handle as *const GifskiHandleInternal;
    g.as_ref()
}

/// The last step:
///  - stops accepting any more frames (gifski_add_frame_* calls are blocked)
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
    let g = Arc::from_raw(g as *const GifskiHandleInternal);

    // dropping of the collector (if any) completes writing
    *g.collector.lock().unwrap() = None;

    let thread = g.write_thread.lock().unwrap().1.take();
    if let Some(thread) = thread {
        thread.join().expect("writer thread failed")
    } else {
        eprintln!("gifski_finish called before any output has been set");
        GifskiError::OK // this will become INVALID_STATE once sync write support is dropped
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
        let write_called = user_data as *mut bool;
        *write_called = true;
        0
    }
    let mut progress_called = 0u32;
    unsafe extern "C" fn pcb(user_data: *mut c_void) -> c_int {
        let progress_called = user_data as *mut u32;
        *progress_called += 1;
        1
    }
    unsafe {
        assert_eq!(GifskiError::OK, gifski_set_progress_callback(g, pcb, (&mut progress_called) as *mut _ as _));
        assert_eq!(GifskiError::OK, gifski_set_write_callback(g, Some(cb), (&mut write_called) as *mut _ as _));
        assert_eq!(GifskiError::INVALID_STATE, gifski_set_progress_callback(g, pcb, (&mut progress_called) as *mut _ as _));
        assert_eq!(GifskiError::OK, gifski_add_frame_rgb(g, 0, 1, 3, 1, &RGB::new(0,0,0), 3.));
        assert_eq!(GifskiError::OK, gifski_add_frame_rgb(g, 0, 1, 3, 1, &RGB::new(0,0,0), 10.));
        assert_eq!(GifskiError::OK, gifski_finish(g));
    }
    assert!(write_called);
    assert_eq!(2, progress_called);
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
    unsafe extern "C" fn cb(_s: usize, _buf: *const u8, _: *mut c_void) -> c_int {
        0
    }
    unsafe {
        assert_eq!(GifskiError::OK, gifski_set_write_callback(g, Some(cb), 0 as _));
        assert_eq!(GifskiError::OTHER, gifski_finish(g));
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
