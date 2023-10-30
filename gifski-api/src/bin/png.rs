
use crate::source::Fps;
use crate::source::Source;
use crate::BinResult;
use gifski::Collector;
use std::path::PathBuf;

pub struct Lodecoder {
    frames: Vec<PathBuf>,
    fps: f32,
}

impl Lodecoder {
    pub fn new(frames: Vec<PathBuf>, params: Fps) -> Self {
        Self { frames, fps: params.fps }
    }
}

impl Source for Lodecoder {
    fn total_frames(&self) -> Option<u64> {
        Some(self.frames.len() as u64)
    }

    #[inline(never)]
    fn collect(&mut self, dest: &mut Collector) -> BinResult<()> {
        let dest = &*dest;
        let fps = f64::from(self.fps);
        let f = std::mem::take(&mut self.frames);
        for (i, frame) in f.into_iter().enumerate() {
            dest.add_frame_png_file(i, frame, i as f64 / fps)?;
        }
        Ok(())
    }
}
