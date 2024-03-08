//! This is for reading GIFs as an input for re-encoding as another GIF

use std::fs::File;
use gif::Decoder;
use gifski::Collector;
use std::path::Path;
use crate::{source::{Fps, Source}, BinResult};

pub struct GifDecoder {
    speed: f32,
    decoder: Decoder<File>,
    screen: gif_dispose::Screen,
}

impl GifDecoder {
    pub fn new(path: &Path, fps: Fps) -> BinResult<Self> {
        let file = std::fs::File::open(path)?;

        let mut gif_opts = gif::DecodeOptions::new();
        // Important:
        gif_opts.set_color_output(gif::ColorOutput::Indexed);

        let decoder = gif_opts.read_info(file)?;
        let screen = gif_dispose::Screen::new_decoder(&decoder);

        Ok(Self {
            speed: fps.speed,
            decoder,
            screen,
        })
    }
}

impl Source for GifDecoder {
    fn total_frames(&self) -> Option<u64> { None }
    fn collect(&mut self, c: &mut Collector) -> BinResult<()> {
        let mut idx = 0;
        let mut delay_ts = 0;
        while let Some(frame) = self.decoder.read_next_frame()? {
            self.screen.blit_frame(frame)?;
            let pixels = self.screen.pixels_rgba().map_buf(|b| b.to_owned());
            let presentation_timestamp = f64::from(delay_ts) * (f64::from(self.speed) / 100.);
            c.add_frame_rgba(idx, pixels, presentation_timestamp)?;
            idx += 1;
            delay_ts += u32::from(frame.delay);
        }
        Ok(())
    }
}
