use source::*;
use gifski::Collector;
use error::*;
use std::path::PathBuf;

pub struct Lodecoder {
    frames: Vec<PathBuf>,
    fps: usize,
}

impl Lodecoder {
    pub fn new(frames: Vec<PathBuf>, fps: usize) -> Self {
        Self {
            frames,
            fps,
        }
    }
}

impl Source for Lodecoder {
    fn total_frames(&self) -> u64 {
        self.frames.len() as u64
    }

    fn collect(&mut self, mut dest: Collector) -> BinResult<()> {
        for (i, frame) in self.frames.drain(..).enumerate() {
            let delay = ((i + 1) * 100 / self.fps) - (i * 100 / self.fps); // See telecine/pulldown.
            dest.add_frame_png_file(i, frame, delay as u16)?;
        }
        Ok(())
    }
}
