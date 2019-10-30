/*
 gifski pngquant-based GIF encoder
 © 2017 Kornel Lesiński

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as
 published by the Free Software Foundation, either version 3 of the
 License, or (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
#![doc(html_logo_url = "https://gif.ski/icon.png")]

use gif;
use imagequant;
use resize;
use lodepng;
use gif_dispose;

#[macro_use] extern crate error_chain;
use rgb::*;
use imgref::*;
use imagequant::*;

mod error;
pub use crate::error::*;
mod ordqueue;
use crate::ordqueue::*;
pub mod progress;
use crate::progress::*;
pub mod c_api;
mod encoderust;

#[cfg(feature = "gifsicle")]
mod encodegifsicle;

use std::path::PathBuf;
use std::io::prelude::*;
use std::sync::Arc;

use std::thread;

type DecodedImage = CatResult<(ImgVec<RGBA8>, u16)>;

#[derive(Copy, Clone, Default)]
pub struct Settings {
    /// Resize to max this width if set
    pub width: Option<u32>,
    /// Resize to max this height if width is set. Note that aspect ratio is not preserved.
    pub height: Option<u32>,
    /// 1-100
    pub quality: u8,
    /// If true, looping is disabled
    pub once: bool,
    /// Lower quality, but faster encode
    pub fast: bool,
}

impl Settings {
    #[cfg(not(feature = "gifsicle"))]
    pub(crate) fn color_quality(&self) -> u8 {
        self.quality
    }

    #[cfg(feature = "gifsicle")]
    pub(crate) fn color_quality(&self) -> u8 {
        (self.quality * 2).min(100)
    }
}

/// Collect frames that will be encoded
///
/// Note that writing will finish only when the collector is dropped.
/// Collect frames on another thread, or call `drop(collector)` before calling `writer.write()`!
pub struct Collector {
    width: Option<u32>,
    height: Option<u32>,
    queue: OrdQueue<DecodedImage>,
}

/// Perform GIF writing
pub struct Writer {
    queue_iter: Option<OrdQueueIter<DecodedImage>>,
    settings: Settings,
}

struct GIFFrame {
    image: ImgVec<u8>,
    pal: Vec<RGBA8>,
    delay: u16,
    dispose: gif::DisposalMethod,
}

trait Encoder {
    fn write_frame(&mut self, frame: &GIFFrame, settings: &Settings) -> CatResult<()>;
    fn finish(&mut self) -> CatResult<()> {
        Ok(())
    }
}

/// Start new encoding
///
/// Encoding is multi-threaded, and the `Collector` and `Writer`
/// can be used on sepate threads.
pub fn new(settings: Settings) -> CatResult<(Collector, Writer)> {
    let (queue, queue_iter) = ordqueue::new(4);

    Ok((
        Collector {
            queue,
            width: settings.width,
            height: settings.height,
        },
        Writer {
            queue_iter: Some(queue_iter),
            settings,
        },
    ))
}

impl Collector {
    /// Frame index starts at 0. Set each frame only once, but you can set them in any order.
    /// Frame delay is in GIF units (1/100s).
    pub fn add_frame_rgba(&mut self, frame_index: usize, image: ImgVec<RGBA8>, delay: u16) -> CatResult<()> {
        self.queue.push(frame_index, Ok((Self::resized_binary_alpha(image, self.width, self.height), delay)))
    }

    /// Read and decode a PNG file from disk. Frame index starts at 0. Frame delay is in GIF units (1/100s)
    pub fn add_frame_png_file(&mut self, frame_index: usize, path: PathBuf, delay: u16) -> CatResult<()> {
        let width = self.width;
        let height = self.height;
        let image = lodepng::decode32_file(&path)
            .chain_err(|| format!("Can't load {}", path.display()))?;

        self.queue.push(frame_index, Ok((Self::resized_binary_alpha(ImgVec::new(image.buffer, image.width, image.height), width, height), delay)))
    }

    fn resized_binary_alpha(mut image: ImgVec<RGBA8>, width: Option<u32>, height: Option<u32>) -> ImgVec<RGBA8> {
        if let Some(width) = width {
            if image.width() != image.stride() {
                let mut contig = Vec::with_capacity(image.width() * image.height());
                contig.extend(image.rows().flat_map(|r| r.iter().cloned()));
                image = ImgVec::new(contig, image.width(), image.height());
            }
            let dst_width = (width as usize).min(image.width());
            let dst_height = height.map(|h| (h as usize).min(image.height())).unwrap_or(image.height() * dst_width / image.width());
            let mut r = resize::new(image.width(), image.height(), dst_width, dst_height, resize::Pixel::RGBA, resize::Type::Lanczos3);
            let mut dst = vec![RGBA::new(0, 0, 0, 0); dst_width * dst_height];
            assert_eq!(image.buf().len(), image.width() * image.height());
            r.resize(image.buf().as_bytes(), dst.as_bytes_mut());
            image = ImgVec::new(dst, dst_width, dst_height)
        }

        const DITHER: [u8; 64] = [
         0*2+8,48*2+8,12*2+8,60*2+8, 3*2+8,51*2+8,15*2+8,63*2+8,
        32*2+8,16*2+8,44*2+8,28*2+8,35*2+8,19*2+8,47*2+8,31*2+8,
         8*2+8,56*2+8, 4*2+8,52*2+8,11*2+8,59*2+8, 7*2+8,55*2+8,
        40*2+8,24*2+8,36*2+8,20*2+8,43*2+8,27*2+8,39*2+8,23*2+8,
         2*2+8,50*2+8,14*2+8,62*2+8, 1*2+8,49*2+8,13*2+8,61*2+8,
        34*2+8,18*2+8,46*2+8,30*2+8,33*2+8,17*2+8,45*2+8,29*2+8,
        10*2+8,58*2+8, 6*2+8,54*2+8, 9*2+8,57*2+8, 5*2+8,53*2+8,
        42*2+8,26*2+8,38*2+8,22*2+8,41*2+8,25*2+8,37*2+8,21*2+8];

        // Make transparency binary
        for (y, row) in image.rows_mut().enumerate() {
            for (x, px) in row.iter_mut().enumerate() {
                if px.a < 255 {
                    px.a = if px.a < DITHER[(y & 7) * 8 + (x & 7)] { 0 } else { 255 };
                }
            }
        }
        image
    }
}

/// Encode collected frames
impl Writer {
    /// `importance_map` is computed from previous and next frame.
    /// Improves quality of pixels visible for longer.
    /// Avoids wasting palette on pixels identical to the background.
    ///
    /// `background` is the previous frame.
    fn quantize(image: ImgRef<'_, RGBA8>, importance_map: &[u8], background: Option<ImgRef<'_, RGBA8>>, settings: &Settings) -> CatResult<(ImgVec<u8>, Vec<RGBA8>)> {
        let mut liq = Attributes::new();
        if settings.fast {
            liq.set_speed(10);
        }
        let quality = if background.is_some() { // not first frame
            settings.color_quality().into()
        } else {
            100 // the first frame is too important to ruin it
        };
        liq.set_quality(0, quality);
        let mut img = liq.new_image_stride(image.buf(), image.width(), image.height(), image.stride(), 0.)?;
        img.set_importance_map(importance_map)?;
        if let Some(bg) = background {
            assert_eq!(bg.width(), bg.stride());
            img.set_background(liq.new_image(bg.buf(), bg.width(), bg.height(), 0.)?)?;
        }
        img.add_fixed_color(RGBA8::new(0, 0, 0, 0));
        let mut res = liq.quantize(&img)?;
        res.set_dithering_level(0.5);

        let (pal, pal_img) = res.remapped(&mut img)?;
        debug_assert_eq!(img.width() * img.height(), pal_img.len());

        Ok((Img::new(pal_img, img.width(), img.height()), pal))
    }

    fn write_frames(write_queue_iter: OrdQueueIter<Arc<GIFFrame>>, enc: &mut dyn Encoder, settings: &Settings, reporter: &mut dyn ProgressReporter) -> CatResult<()> {
        for f in write_queue_iter {
            enc.write_frame(&f, settings)?;
            if !reporter.increase() {
                Err(ErrorKind::Aborted)?
            }
        }
        enc.finish()?;
        Ok(())
    }

    /// Start writing frames. This function will not return until `Collector` is dropped.
    ///
    /// `outfile` can be any writer, such as `File` or `&mut Vec`.
    ///
    /// `ProgressReporter.increase()` is called each time a new frame is being written.
    #[allow(unused_mut)]
    pub fn write<W: Write>(self, mut writer: W, reporter: &mut dyn ProgressReporter) -> CatResult<()> {

        #[cfg(feature = "gifsicle")]
        {
            let encoder: &mut dyn Encoder;
            let mut gifsicle;
            let mut rustgif;
            if self.settings.quality < 100 {
                let loss = (100 - self.settings.quality as u32) * 6;
                gifsicle = encodegifsicle::Gifsicle::new(loss, &mut writer);
                encoder = &mut gifsicle;
            } else {
                rustgif = encoderust::RustEncoder::new(writer);
                encoder = &mut rustgif;
            }
            self.write_with_encoder(encoder, reporter)
        }
        #[cfg(not(feature = "gifsicle"))]
        {
            self.write_with_encoder(&mut encoderust::RustEncoder::new(writer), reporter)
        }
    }

    fn write_with_encoder(mut self, encoder: &mut dyn Encoder, reporter: &mut dyn ProgressReporter) -> CatResult<()> {
        let (write_queue, write_queue_iter) = ordqueue::new(4);
        let queue_iter = self.queue_iter.take().unwrap();
        let settings = self.settings;
        let make_thread = thread::spawn(move || {
            Self::make_frames(queue_iter, write_queue, &settings)
        });
        Self::write_frames(write_queue_iter, encoder, &self.settings, reporter)?;
        make_thread.join().unwrap()?;
        Ok(())
    }

    fn make_frames(queue_iter: OrdQueueIter<DecodedImage>, mut write_queue: OrdQueue<Arc<GIFFrame>>, settings: &Settings) -> CatResult<()> {
        let mut decode_iter = queue_iter.enumerate().map(|(i, tmp)| tmp.map(|(image, delay)| (i, image, delay)));

        let mut screen = None;
        let mut curr_frame = if let Some(a) = decode_iter.next() {
            Some(a?)
        } else {
            Err("Found no usable frames to encode")?
        };
        let mut importance_map = vec![255u8; curr_frame.as_ref().unwrap().1.buf().len()];
        let mut next_frame = if let Some(a) = decode_iter.next() {
            Some(a?)
        } else {
            None
        };

        let mut previous_frame_dispose = gif::DisposalMethod::Background;
        while let Some((i, image, delay)) = curr_frame.take() {
            curr_frame = next_frame.take();
            next_frame = if let Some(a) = decode_iter.next() {
                Some(a?)
            } else {
                None
            };

            let mut dispose = gif::DisposalMethod::Keep;

            if let Some((_, ref next, _)) = next_frame {
                if next.width() != image.width() || next.height() != image.height() {
                    Err(format!("Frame {} has wrong size ({}×{}, expected {}×{})", i+1,
                        next.width(), next.height(), image.width(), image.height()))?;
                }

                debug_assert_eq!(next.width(), image.width());
                importance_map.clear();
                importance_map.extend(next.rows().zip(image.rows()).flat_map(|(n, curr)| n.iter().cloned().zip(curr.iter().cloned())).map(|(n, curr)| {
                    if n.a < curr.a {
                        dispose = gif::DisposalMethod::Background;
                    }
                    // Even if next frame completely overwrites it, it's still somewhat important to display current one
                    // but pixels that will stay unchanged should have higher quality
                    255 - (colordiff(n, curr) / (255 * 255 * 6 / 170)) as u8
                }));
            };

            if screen.is_none() {
                screen = Some(gif_dispose::Screen::new(image.width(), image.height(), RGBA8::new(0, 0, 0, 0), None));
            }
            let screen = screen.as_mut().unwrap();

            let has_prev_frame = i > 0 && previous_frame_dispose == gif::DisposalMethod::Keep;
            if has_prev_frame {
                let q = 100 - u32::from(settings.color_quality());
                let min_diff = 80 + q * q;
                debug_assert_eq!(image.width(), screen.pixels.width());
                importance_map.chunks_mut(image.width()).zip(screen.pixels.rows().zip(image.rows()))
                .flat_map(|(px, (a,b))| {
                    px.iter_mut().zip(a.iter().cloned().zip(b.iter().cloned()))
                })
                .for_each(|(px, (a,b))| {
                    // TODO: try comparing with max-quality dithered non-transparent frame, but at half res to avoid dithering confusing the results
                    // and pick pixels/areas that are better left transparent?

                    let diff = colordiff(a,b);
                    // if pixels are close or identical, no weight on them
                    *px = if diff < min_diff {
                        0
                    } else {
                        // clip max value, since if something's different it doesn't matter how much, it has to be displayed anyway
                        // but multiply by previous map last, since it already decided non-max value
                        let t = diff / 32;
                        ((t * t).min(256) as u16 * u16::from(*px) / 256) as u8
                    }
                });
            }

            let (image8, image8_pal) = {
                let bg = if has_prev_frame { Some(screen.pixels.as_ref()) } else { None };
                Self::quantize(image.as_ref(), &importance_map, bg, settings)?
            };

            let transparent_index = image8_pal.iter().position(|p| p.a == 0).map(|i| i as u8);
            let frame = Arc::new(GIFFrame {
                image: image8,
                pal: image8_pal,
                dispose,
                delay,
            });

            write_queue.push(i, frame.clone())?;
            screen.blit(Some(&frame.pal), dispose, 0, 0, frame.image.as_ref(), transparent_index)?;
            previous_frame_dispose = dispose;
        }

        Ok(())
    }
}

#[inline]
fn colordiff(a: RGBA8, b: RGBA8) -> u32 {
    if a.a == 0 || b.a == 0 {
        return 255 * 255 * 6;
    }
    (i32::from(i16::from(a.r) - i16::from(b.r)) * i32::from(i16::from(a.r) - i16::from(b.r))) as u32 * 2 +
    (i32::from(i16::from(a.g) - i16::from(b.g)) * i32::from(i16::from(a.g) - i16::from(b.g))) as u32 * 3 +
    (i32::from(i16::from(a.b) - i16::from(b.b)) * i32::from(i16::from(a.b) - i16::from(b.b))) as u32
}
