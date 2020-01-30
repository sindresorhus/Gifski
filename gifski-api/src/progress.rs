pub use pbr::ProgressBar;
use std::io::Stdout;
use std::os::raw::{c_int, c_void};

/// A trait that is used to report progress to some consumer.
pub trait ProgressReporter: Send {
    /// Increase the progress counter. Return `false` to abort processing.
    fn increase(&mut self) -> bool;

    /// Mark the progress as done.
    fn done(&mut self, msg: &str);
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
impl ProgressReporter for ProgressBar<Stdout> {
    fn increase(&mut self) -> bool {
        self.inc();
        true
    }

    fn done(&mut self, msg: &str) {
        self.finish_print(msg);
    }
}
