use std::io::Stdout;
use std::ptr;
use std::os::raw::c_int;
use std::ffi::CString;
pub use pbr::ProgressBar;

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
    callback: unsafe fn(*const i8) -> c_int,
}

impl ProgressCallback {
    pub fn new(callback: unsafe fn(*const i8) -> c_int) -> Self {
        Self {
            callback,
        }
    }
}

impl ProgressReporter for NoProgress {
    fn increase(&mut self) -> bool {true}
    fn done(&mut self, _msg: &str) {}
}

impl ProgressReporter for ProgressCallback {
    fn increase(&mut self)-> bool {
        unsafe {
            (self.callback)(ptr::null()) == 1
        }
    }
    fn done(&mut self, msg: &str) {
        let cmsg = CString::new(msg).unwrap();
        unsafe {
            (self.callback)(cmsg.as_ptr());
        }
    }
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
