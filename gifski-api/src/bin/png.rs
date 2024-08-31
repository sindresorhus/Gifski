
use crate::source::Fps;
use crate::source::Source;
use crate::BinResult;
use gifski::Collector;
use std::path::PathBuf;

pub struct Lodecoder {
    frames: Vec<PathBuf>,
    fps: f64,
}

impl Lodecoder {
    pub fn new(frames: Vec<PathBuf>, params: Fps) -> Self {
        Self { frames, fps: f64::from(params.fps) * f64::from(params.speed) }
    }
}

impl Source for Lodecoder {
    fn total_frames(&self) -> Option<u64> {
        Some(self.frames.len() as u64)
    }

    #[inline(never)]
    fn collect(&mut self, dest: &mut Collector) -> BinResult<()> {
        let dest = &*dest;
        let f = std::mem::take(&mut self.frames);
        for (i, frame) in f.into_iter().enumerate() {
            dest.add_frame_png_file(i, frame, i as f64 / self.fps)?;
        }
        Ok(())
    }
}
