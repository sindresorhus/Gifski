use crate::error::CatResult;
use crate::GIFFrame;
use crate::Settings;
use crate::Encoder;
use rgb::ComponentBytes;
use std::io::Write;

pub(crate) struct RustEncoder<W: Write> {
    writer: Option<W>,
    gif_enc: Option<gif::Encoder<W>>,
}

impl<W: Write> RustEncoder<W> {
    pub fn new(writer: W) -> Self {
        Self {
            writer: Some(writer),
            gif_enc: None,
        }
    }
}

impl<W: Write> Encoder for RustEncoder<W> {
    fn write_frame(&mut self, f: GIFFrame, delay: u16, settings: &Settings) -> CatResult<()> {
        let GIFFrame {left, top, pal, image, screen_width, screen_height, dispose, transparent_index} = f;

        let writer = &mut self.writer;

        let enc = match self.gif_enc {
            None => {
                let w = writer.take().ok_or(crate::Error::ThreadSend)?;
                let mut enc = gif::Encoder::new(w, screen_width, screen_height, &[])?;
                enc.write_extension(gif::ExtensionData::Repetitions(settings.repeat))?;
                self.gif_enc.get_or_insert(enc)
            },
            Some(ref mut enc) => enc,
        };

        let (buffer, width, height) = image.into_contiguous_buf();

        let mut pal_rgb = Vec::with_capacity(3 * pal.len());
        for p in &pal {
            pal_rgb.extend_from_slice([p.rgb()].as_bytes());
        }

        enc.write_frame(&gif::Frame {
            delay,
            dispose,
            transparent: transparent_index,
            needs_user_input: false,
            top,
            left,
            width: width as u16,
            height: height as u16,
            interlaced: false,
            palette: Some(pal_rgb),
            buffer: buffer.into(),
        })?;
        Ok(())
    }
}
