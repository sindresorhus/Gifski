//! For tracking conversion progress and aborting early

#[cfg(feature = "pbr")]
#[doc(hidden)]
#[deprecated(note = "The pbr dependency is no longer exposed. Please use a newtype pattern and write your own trait impl for it")]
pub use pbr::ProgressBar;

use std::os::raw::{c_int, c_void};

/// A trait that is used to report progress to some consumer.
pub trait ProgressReporter: Send {
    /// Called after each frame has been written.
    ///
    /// This method may return `false` to abort processing.
    fn increase(&mut self) -> bool;

    /// File size so far
    fn written_bytes(&mut self, _current_file_size_in_bytes: u64) {}

    /// Not used :(
    /// Writing is done when `Writer::write()` call returns
    fn done(&mut self, _msg: &str) {}
}

/// No-op progress reporter
pub struct NoProgress {}

/// For C
pub struct ProgressCallback {
    callback: unsafe extern "C" fn(*mut c_void) -> c_int,
    arg: *mut c_void,
}

unsafe impl Send for ProgressCallback {}

impl ProgressCallback {
    pub fn new(callback: unsafe extern "C" fn(*mut c_void) -> c_int, arg: *mut c_void) -> Self {
        Self { callback, arg }
    }
}

impl ProgressReporter for NoProgress {
    fn increase(&mut self) -> bool {
        true
    }
    fn done(&mut self, _msg: &str) {}
}

impl ProgressReporter for ProgressCallback {
    fn increase(&mut self) -> bool {
        unsafe { (self.callback)(self.arg) == 1 }
    }
    fn done(&mut self, _msg: &str) {}
}

/// Implement the progress reporter trait for a progress bar,
/// to make it usable for frame processing reporting.
#[cfg(feature = "pbr")]
impl<T> ProgressReporter for ProgressBar<T> where T: std::io::Write + Send {
    fn increase(&mut self) -> bool {
        self.inc();
        true
    }

    fn done(&mut self, msg: &str) {
        self.finish_print(msg);
    }
}
