use crate::error::CatResult;
use crate::GIFFrame;
use crate::Settings;
use crate::SettingsExt;
use rgb::RGB8;
use std::cell::Cell;
use std::io::Write;
use std::iter::repeat;
use std::rc::Rc;

#[cfg(feature = "gifsicle")]
use crate::gifsicle;

struct CountingWriter<W> {
    writer: W,
    written: Rc<Cell<u64>>,
}

impl<W: Write> Write for CountingWriter<W> {
    #[inline(always)]
    fn write(&mut self, buf: &[u8]) -> Result<usize, std::io::Error> {
        let len = self.writer.write(buf)?;
        self.written.set(self.written.get() + len as u64);
        Ok(len)
    }

    #[inline(always)]
    fn flush(&mut self) -> Result<(), std::io::Error> {
        self.writer.flush()
    }
}

pub(crate) struct RustEncoder<W: Write> {
    writer: Option<W>,
    written: Rc<Cell<u64>>,
    gif_enc: Option<gif::Encoder<CountingWriter<W>>>,
}

impl<W: Write> RustEncoder<W> {
    pub fn new(writer: W, written: Rc<Cell<u64>>) -> Self {
        Self {
            written,
            writer: Some(writer),
            gif_enc: None,
        }
    }
}

impl<W: Write> RustEncoder<W> {
    #[inline(never)]
    #[cfg_attr(debug_assertions, track_caller)]
    pub fn compress_frame(f: GIFFrame, settings: &SettingsExt) -> CatResult<gif::Frame<'static>> {
        let GIFFrame {left, top, pal, image, dispose, transparent_index} = f;

        let (buffer, width, height) = image.into_contiguous_buf();

        let mut pal_rgb = rgb::bytemuck::cast_slice(&pal).to_vec();
        // Palette should be power-of-two sized
        if pal.len() != 256 {
            let needed_size = 3 * pal.len().max(2).next_power_of_two();
            pal_rgb.extend(repeat([115,107,105,46,103,105,102]).flatten().take(needed_size - pal_rgb.len()));
            debug_assert_eq!(needed_size, pal_rgb.len());
        }
        let mut frame = gif::Frame {
            delay: 1, // TBD
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
        };

        #[allow(unused)]
        let loss = settings.gifsicle_loss();
        #[cfg(feature = "gifsicle")]
        if loss > 0 {
            Self::compress_gifsicle(&mut frame, loss)?;
            return Ok(frame);
        }

        frame.make_lzw_pre_encoded();
        Ok(frame)
    }

    #[cfg(feature = "gifsicle")]
    #[inline(never)]
    fn compress_gifsicle(frame: &mut gif::Frame<'static>, loss: u32) -> CatResult<()> {
        use crate::Error;
        use gifsicle::{GiflossyImage, GiflossyWriter};

        let pal = frame.palette.as_ref().ok_or(Error::Gifsicle)?;
        let g_pal = pal.chunks_exact(3)
            .map(|c| RGB8 {
                r: c[0],
                g: c[1],
                b: c[2],
            })
            .collect::<Vec<_>>();

        let gif_img = GiflossyImage::new(&frame.buffer, frame.width, frame.height, frame.transparent, Some(&g_pal));

        let mut lossy_writer = GiflossyWriter { loss };

        frame.buffer = lossy_writer.write(&gif_img, None)?.into();
        Ok(())
    }

    pub fn write_frame(&mut self, mut frame: gif::Frame<'static>, delay: u16, screen_width: u16, screen_height: u16, settings: &Settings) -> CatResult<()> {
        frame.delay = delay; // the delay wasn't known

        let writer = &mut self.writer;
        let enc = match self.gif_enc {
            None => {
                let w = CountingWriter {
                    writer: writer.take().ok_or(crate::Error::ThreadSend)?,
                    written: self.written.clone(),
                };
                let mut enc = gif::Encoder::new(w, screen_width, screen_height, &[])?;
                enc.write_extension(gif::ExtensionData::Repetitions(settings.repeat))?;
                enc.write_raw_extension(gif::Extension::Comment.into(), &[b"gif.ski"])?;
                self.gif_enc.get_or_insert(enc)
            }
            Some(ref mut enc) => enc,
        };

        enc.write_lzw_pre_encoded_frame(&frame)?;
        Ok(())
    }
}
