use crate::error::*;
use crate::source::*;
use gifski::Collector;
use std::path::PathBuf;

pub struct Lodecoder {
    frames: Vec<PathBuf>,
    fps: usize,
}

impl Lodecoder {
    pub fn new(frames: Vec<PathBuf>, fps: usize) -> Self {
        Self { frames, fps }
    }
}

impl Source for Lodecoder {
    fn total_frames(&self) -> u64 {
        self.frames.len() as u64
    }

    fn collect(&mut self, mut dest: Collector) -> BinResult<()> {
        for (i, frame) in self.frames.drain(..).enumerate() {
            dest.add_frame_png_file(i, frame, i as f64 / self.fps as f64)?;
        }
        Ok(())
    }
}
