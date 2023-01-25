use crate::SettingsExt;
use crate::error::CatResult;
use crate::GIFFrame;
use crate::Settings;
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

impl<W: Write> RustEncoder<W> {
    pub fn compress_frame(f: GIFFrame, settings: &SettingsExt) -> CatResult<gif::Frame<'static>> {
        let GIFFrame {left, top, pal, image, dispose, transparent_index} = f;

        let (buffer, width, height) = image.into_contiguous_buf();

        let mut pal_rgb = Vec::with_capacity(3 * pal.len());
        for p in &pal {
            pal_rgb.extend_from_slice([p.rgb()].as_bytes());
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
    fn compress_gifsicle(frame: &mut gif::Frame<'static>, loss: u32) -> CatResult<()> {
        use crate::Error;
        use gifsicle::*;
        use std::mem::MaybeUninit;
        use std::ptr;

        let pal = frame.palette.as_ref().ok_or(Error::Gifsicle)?;

        let min_code_size = (pal.len() as u32 / 3).max(2).next_power_of_two().trailing_zeros();

        unsafe {
            let g = Gif_NewImage().as_mut().ok_or(crate::Error::Gifsicle)?;
            let mut g = scopeguard::guard(g, |g| {
                Gif_DeleteImage(g);
            });
            g.top = frame.top;
            g.left = frame.left;
            g.delay = frame.delay; // unused here
            g.width = frame.width;
            g.height = frame.height;
            g.disposal = match frame.dispose {
                gif::DisposalMethod::Any => Disposal::None,
                gif::DisposalMethod::Keep => Disposal::Asis,
                gif::DisposalMethod::Background => Disposal::Background,
                gif::DisposalMethod::Previous => Disposal::Previous,
            } as _;
            g.transparent = frame.transparent.map_or(-1, i16::from);

            g.local = Gif_NewFullColormap(0, pal.len() as _); // it's owned by the image
            if g.local.is_null() {
                return Err(Error::Gifsicle);
            }
            for c in pal.chunks_exact(3) {
                Gif_AddColor(g.local, &mut Gif_Color {
                    gfc_red: c[0],
                    gfc_green: c[1],
                    gfc_blue: c[2],
                    haspixel: 0, // dunno?
                    pixel: 0,
                }, -1);
            }
            let gci = Gif_CompressInfo {
                flags: 0,
                loss: loss as _,
                padding: [ptr::null_mut(); 7],
            };

            let mut grr = MaybeUninit::zeroed();
            if gifsicle::Gif_WriterInit(&mut grr, ptr::null_mut(), &gci) == 0 {
                return Err(Error::Gifsicle);
            }
            let mut grr = scopeguard::guard(grr.assume_init_mut(), |grr| {
                gifsicle::Gif_WriterCleanup(grr);
            });

            let mut res = Gif_SetUncompressedImage(&mut **g, frame.buffer.as_ptr() as *mut u8, None, 0);
            if res != 0 {
                res = gifsicle::Gif_WriteCompressedData(ptr::null_mut(), *g, min_code_size as _, &mut **grr);
            }
            drop(g);
            if res == 0 {
                return Err(Error::Gifsicle);
            }
            frame.buffer = extract_chunks(&grr).ok_or(Error::Gifsicle)?.into();
        }
        Ok(())
    }

    pub fn write_frame(&mut self, mut frame: gif::Frame<'static>, delay: u16, screen_width: u16, screen_height: u16, settings: &Settings) -> CatResult<()> {
        frame.delay = delay; // the delay wasn't known

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

        enc.write_lzw_pre_encoded_frame(&frame)?;
        Ok(())
    }
}

#[cfg(feature = "gifsicle")]
unsafe fn extract_chunks(grr: &gifsicle::Gif_Writer) -> Option<Vec<u8>> {
    let encoded = grr.v.as_ref()?;
    let encoded = std::slice::from_raw_parts(encoded, grr.pos as usize);
    let mut out = Vec::with_capacity(encoded.len());
    let (&code_size, mut chunks) = encoded.split_first()?;
    out.push(code_size);
    while let Some((&next_len, rest)) = chunks.split_first() {
        let next_len = next_len as usize;
        if next_len == 0 || next_len > rest.len() {
            break;
        }
        let (chunk, rest) = rest.split_at(next_len);
        out.extend_from_slice(chunk);
        chunks = rest;
    }
    Some(out)
}
