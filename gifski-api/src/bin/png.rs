use crate::source::Fps;
use crate::source::Source;
use crate::BinResult;
use gifski::Collector;
use std::path::PathBuf;

pub struct Lodecoder {
    frames: Vec<PathBuf>,
    fps: f32,
    thread_pool_size: u8,
}

impl Lodecoder {
    pub fn new(frames: Vec<PathBuf>, params: Fps, thread_pool_size: u8) -> Self {
        Self { frames, fps: params.fps, thread_pool_size }
    }
}

impl Source for Lodecoder {
    fn total_frames(&self) -> u64 {
        self.frames.len() as u64
    }

    fn collect(&mut self, dest: &mut Collector) -> BinResult<()> {
        let dest = &*dest;
        let fps = f64::from(self.fps);
        let f = std::mem::take(&mut self.frames);
        Ok(gifski::private_minipool(self.thread_pool_size, "decode", move |s| {
            Ok(f.into_iter().enumerate().try_for_each(|f| s.send(f))?)
        }, move |(i, frame)| {
            dest.add_frame_png_file(i, frame, i as f64 / fps)
        })?)
    }
}
