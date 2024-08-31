//! For adding frames to the encoder
//!
//! [`gifski::new()`][crate::new] returns the [`Collector`] that collects animation frames,
//! and a [`Writer`][crate::Writer] that performs compression and I/O.

pub use imgref::ImgVec;
pub use rgb::{RGB8, RGBA8};

use crate::error::GifResult;
use crossbeam_channel::Sender;

#[cfg(feature = "png")]
use std::path::PathBuf;

pub(crate) enum FrameSource {
    Pixels(ImgVec<RGBA8>),
    #[cfg(feature = "png")]
    PngData(Vec<u8>),
    #[cfg(all(feature = "png", not(target_arch = "wasm32")))]
    Path(PathBuf),
}

pub(crate) struct InputFrame {
    /// The pixels to resize and encode
    pub frame: FrameSource,
    /// Time in seconds when to display the frame. First frame should start at 0.
    pub presentation_timestamp: f64,
    pub frame_index: usize,
}

pub(crate) struct InputFrameResized {
    /// The pixels to encode
    pub frame: ImgVec<RGBA8>,
    /// The same as above, but with smart blur applied (for denoiser)
    pub frame_blurred: ImgVec<RGB8>,
    /// Time in seconds when to display the frame. First frame should start at 0.
    pub presentation_timestamp: f64,
}

/// Collect frames that will be encoded
///
/// Note that writing will finish only when the collector is dropped.
/// Collect frames on another thread, or call `drop(collector)` before calling `writer.write()`!
pub struct Collector {
    pub(crate) queue: Sender<InputFrame>,
}

impl Collector {
    /// Frame index starts at 0.
    ///
    /// Set each frame (index) only once, but you can set them in any order. However, out-of-order frames
    /// will be buffered in RAM, and big gaps in frame indices will cause high memory usage.
    ///
    /// Presentation timestamp is time in seconds (since file start at 0) when this frame is to be displayed.
    ///
    /// If the first frame doesn't start at pts=0, the delay will be used for the last frame.
    ///
    /// If this function appears to be stuck after a few frames, it's because [`crate::Writer::write()`] is not running.
    #[cfg_attr(debug_assertions, track_caller)]
    pub fn add_frame_rgba(&self, frame_index: usize, frame: ImgVec<RGBA8>, presentation_timestamp: f64) -> GifResult<()> {
        debug_assert!(frame_index == 0 || presentation_timestamp > 0.);
        self.queue.send(InputFrame {
            frame_index,
            frame: FrameSource::Pixels(frame),
            presentation_timestamp,
        })?;
        Ok(())
    }

    /// Decode a frame from in-memory PNG-compressed data.
    ///
    /// Frame index starts at 0.
    /// Set each frame (index) only once, but you can set them in any order. However, out-of-order frames
    /// will be buffered in RAM, and big gaps in frame indices will cause high memory usage.
    ///
    /// Presentation timestamp is time in seconds (since file start at 0) when this frame is to be displayed.
    ///
    /// If the first frame doesn't start at pts=0, the delay will be used for the last frame.
    ///
    /// If this function appears to be stuck after a few frames, it's because [`crate::Writer::write()`] is not running.
    #[cfg(feature = "png")]
    #[inline]
    pub fn add_frame_png_data(&self, frame_index: usize, png_data: Vec<u8>, presentation_timestamp: f64) -> GifResult<()> {
        self.queue.send(InputFrame {
            frame: FrameSource::PngData(png_data),
            presentation_timestamp,
            frame_index,
        })?;
        Ok(())
    }

    /// Read and decode a PNG file from disk.
    ///
    /// Frame index starts at 0.
    /// Set each frame (index) only once, but you can set them in any order.
    ///
    /// Presentation timestamp is time in seconds (since file start at 0) when this frame is to be displayed.
    ///
    /// If the first frame doesn't start at pts=0, the delay will be used for the last frame.
    ///
    /// If this function appears to be stuck after a few frames, it's because [`crate::Writer::write()`] is not running.
    #[cfg(feature = "png")]
    pub fn add_frame_png_file(&self, frame_index: usize, path: PathBuf, presentation_timestamp: f64) -> GifResult<()> {
        self.queue.send(InputFrame {
            frame: FrameSource::Path(path),
            presentation_timestamp,
            frame_index,
        })?;
        Ok(())
    }
}
