use crate::Encoder;
use crate::error::*;
use crate::GIFFrame;
use crate::Settings;
use gifsicle::*;
use std::ptr;
use std::io::Write;

pub(crate) struct Gifsicle<'w> {
    gfs: *mut Gif_Stream,
    gif_writer: *mut Gif_Writer,
    out: &'w mut dyn Write,
    info: Gif_CompressInfo,
}

impl<'w> Gifsicle<'w> {
    pub fn new(loss: u32, out: &'w mut (dyn std::io::Write + 'w)) -> Self {
        unsafe {
            let mut g = Self {
                gfs: ptr::null_mut(),
                gif_writer: ptr::null_mut(),
                info: std::mem::zeroed(),
                out,
            };
            Gif_InitCompressInfo(&mut g.info);
            g.info.loss = loss as _;
            g
        }
    }

    fn flush_writer(&mut self) -> CatResult<()> {
        unsafe {
            if (*self.gif_writer).pos > 0 {
                let buf_start = (*self.gif_writer).v.as_mut().ok_or(ErrorKind::Gifsicle)?;
                let buf = std::slice::from_raw_parts(buf_start, (*self.gif_writer).pos as usize);
                self.out.write_all(buf)?;
                (*self.gif_writer).pos = 0;
            }
        }
        Ok(())
    }
}

impl Drop for Gifsicle<'_> {
    fn drop(&mut self) {
        unsafe {
            if !self.gif_writer.is_null() {
                Gif_IncrementalWriteComplete(self.gif_writer, self.gfs);
            }
            Gif_DeleteStream(self.gfs);
        }
    }
}

impl Encoder for Gifsicle<'_> {
    fn finish(&mut self) -> CatResult<()> {
        if !self.gif_writer.is_null() {
            self.flush_writer()?;
            // fun fact: can't flush after the last write, because the writer gets freed,
            // but the last write is literally just `;` (we don't use comments/extensions)
            self.out.write_all(std::slice::from_ref(&b';'))?;
            unsafe {
                Gif_IncrementalWriteComplete(self.gif_writer, self.gfs);
            }
            self.gif_writer = ptr::null_mut();
        }
        Ok(())
    }
    fn write_frame(&mut self, frame: &GIFFrame, settings: &Settings) -> CatResult<()> {
        let GIFFrame {ref pal, ref image, delay, dispose} = *frame;

        if self.gfs.is_null() {
            let gfs = unsafe {
                self.gfs = gifsicle::Gif_NewStream();
                self.gfs.as_mut().ok_or(ErrorKind::Gifsicle)?
            };
            gfs.screen_width = image.width() as _;
            gfs.screen_height = image.height() as _;
            gfs.loopcount = if settings.once {1} else {-1};
            unsafe {
                self.gif_writer = Gif_IncrementalWriteFileInit(gfs, &self.info, ptr::null_mut());
                if self.gif_writer.is_null() {
                    Err(ErrorKind::Gifsicle)?;
                }
            }
        }

        let g = unsafe {
            Gif_NewImage().as_mut().ok_or(ErrorKind::Gifsicle)?
        };
        g.delay = delay;
        g.width = image.width() as u16;
        g.height = image.height() as u16;
        g.disposal = match dispose {
            gif::DisposalMethod::Any => Disposal::None,
            gif::DisposalMethod::Keep => Disposal::Asis,
            gif::DisposalMethod::Background => Disposal::Background,
            gif::DisposalMethod::Previous => Disposal::Previous,
        } as _;

        g.local = unsafe {Gif_NewFullColormap(0, pal.len() as _)}; // it's owned by the image
        for (i, c) in pal.iter().enumerate() {
            if c.a == 0 {
                g.transparent = i as _;
            }
            unsafe {
                Gif_AddColor((*g).local, &mut Gif_Color {
                    gfc_red: c.r,
                    gfc_green: c.g,
                    gfc_blue: c.b,

                    haspixel: 0, // dunno?
                    pixel: 0,
                }, -1);
            }
        }
        unsafe {
            if 0 == Gif_SetUncompressedImage(g, image.buf().as_ptr() as *mut u8, None, 0) {
                Gif_DeleteImage(g);
                Err(ErrorKind::Gifsicle)?;
            }
            let res = Gif_IncrementalWriteImage(self.gif_writer, self.gfs, g);
            Gif_DeleteImage(g);
            if 0 == res {
                Err(ErrorKind::Gifsicle)?;
            }
            self.flush_writer()?;
        }
        Ok(())
    }
}
