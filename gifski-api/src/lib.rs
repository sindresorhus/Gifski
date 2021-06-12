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

#[macro_use]
extern crate quick_error;

use imagequant::*;
use imgref::*;
use rgb::*;

mod error;
pub use crate::error::*;
mod ordqueue;
use crate::ordqueue::*;
pub mod progress;
use crate::progress::*;
pub mod c_api;
mod denoise;
use crate::denoise::*;
mod encoderust;

#[cfg(feature = "gifsicle")]
mod encodegifsicle;

use crossbeam_channel::{Receiver, Sender};
use std::io::prelude::*;
use std::path::PathBuf;
use std::thread;
use std::borrow::Cow;

type DecodedImage = CatResult<(ImgVec<RGBA8>, f64)>;

/// Number of repetitions
#[derive(Debug, Copy, Clone)]
pub enum Repeat {
    Finite(u16),
    Infinite,
}

/// Encoding settings for the `new()` function
#[derive(Copy, Clone)]
pub struct Settings {
    /// Resize to max this width if non-0.
    pub width: Option<u32>,
    /// Resize to max this height if width is non-0. Note that aspect ratio is not preserved.
    pub height: Option<u32>,
    /// 1-100, but useful range is 50-100. Recommended to set to 100.
    pub quality: u8,
    /// Lower quality, but faster encode.
    pub fast: bool,
    /// Sets the looping method for the image sequence.
    pub repeat: Repeat,
}

impl Settings {
    /// quality is used in other places, like gifsicle or frame differences,
    /// and it's better to lower quality there before ruining quantization
    pub(crate) fn color_quality(&self) -> u8 {
        (self.quality as u16 * 4 / 3).min(100) as u8
    }

    /// add_frame is going to resize the images to this size.
    pub fn dimensions_for_image(&self, width: usize, height: usize) -> (usize, usize) {
        dimensions_for_image((width, height), (self.width, self.height))
    }

    pub(crate) fn gifsicle_loss(&self) -> u32 {
        (100. / 6. - self.quality as f32 / 6.).powf(1.75).ceil() as u32
    }
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            width: None, height: None,
            quality: 100,
            fast: false,
            repeat: Repeat::Infinite,
        }
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
    /// Input frame decoder results
    queue_iter: Option<OrdQueueIter<DecodedImage>>,
    settings: Settings,
}

struct GIFFrame {
    left: u16,
    top: u16,
    screen_width: u16,
    screen_height: u16,
    image: ImgVec<u8>,
    pal: Vec<RGBA8>,
    dispose: gif::DisposalMethod,
    transparent_index: Option<u8>,
}

trait Encoder {
    fn write_frame(&mut self, frame: GIFFrame, delay: u16, settings: &Settings) -> CatResult<()>;
    fn finish(&mut self) -> CatResult<()> {
        Ok(())
    }
}

/// Frame before quantization
struct DiffMessage {
    /// 1..
    ordinal_frame_number: usize,
    /// presentation timestamp of the next frame (i.e. when this frame finishes being displayed)
    end_pts: f64,
    dispose: gif::DisposalMethod,
    image: ImgVec<RGBA8>,
    importance_map: Vec<u8>,
}

/// Frame post quantization, before remap
struct RemapMessage {
    /// 1..
    ordinal_frame_number: usize,
    end_pts: f64,
    dispose: gif::DisposalMethod,
    liq: Attributes,
    remap: QuantizationResult,
    liq_image: Image<'static>,
}

/// Frame post quantization and remap
struct FrameMessage {
    /// 1..
    ordinal_frame_number: usize,
    end_pts: f64,
    frame: GIFFrame,
}

/// Start new encoding
///
/// Encoding is multi-threaded, and the `Collector` and `Writer`
/// can be used on sepate threads.
///
/// You feed input frames to the `Collector`, and ask the `Writer` to
/// start writing the GIF.
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
    /// Frame index starts at 0.
    ///
    /// Set each frame (index) only once, but you can set them in any order.
    ///
    /// Presentation timestamp is time in seconds (since file start at 0) when this frame is to be displayed.
    ///
    /// If the first frame doesn't start at pts=0, the delay will be used for the last frame.
    pub fn add_frame_rgba(&mut self, frame_index: usize, image: ImgVec<RGBA8>, presentation_timestamp: f64) -> CatResult<()> {
        self.queue.push(frame_index, Ok((Self::resized_binary_alpha(image.into(), self.width, self.height)?, presentation_timestamp)))
    }

    pub(crate) fn add_frame_rgba_cow(&mut self, frame_index: usize, image: Img<Cow<[RGBA8]>>, presentation_timestamp: f64) -> CatResult<()> {
        self.queue.push(frame_index, Ok((Self::resized_binary_alpha(image, self.width, self.height)?, presentation_timestamp)))
    }

    /// Read and decode a PNG file from disk.
    ///
    /// Frame index starts at 0.
    ///
    /// Presentation timestamp is time in seconds (since file start at 0) when this frame is to be displayed.
    ///
    /// If the first frame doesn't start at pts=0, the delay will be used for the last frame.
    pub fn add_frame_png_file(&mut self, frame_index: usize, path: PathBuf, presentation_timestamp: f64) -> CatResult<()> {
        let width = self.width;
        let height = self.height;
        let image = lodepng::decode32_file(&path)
            .map_err(|err| Error::PNG(format!("Can't load {}: {}", path.display(), err)))?;

        let image = Img::new(image.buffer.into(), image.width, image.height);
        self.queue.push(frame_index, Ok((Self::resized_binary_alpha(image, width, height)?, presentation_timestamp)))
    }

    #[allow(clippy::identity_op)]
    #[allow(clippy::erasing_op)]
    fn resized_binary_alpha(image: Img<Cow<[RGBA8]>>, width: Option<u32>, height: Option<u32>) -> CatResult<ImgVec<RGBA8>> {
        let (width, height) = dimensions_for_image((image.width(), image.height()), (width, height));

        let mut image = if width != image.width() || height != image.height() {
            let tmp = image.as_ref();
            let (buf, img_width, img_height) = tmp.to_contiguous_buf();
            assert_eq!(buf.len(), img_width * img_height);

            let mut r = resize::new(img_width, img_height, width, height, resize::Pixel::RGBA8P, resize::Type::Lanczos3)?;
            let mut dst = vec![RGBA8::new(0, 0, 0, 0); width * height];
            r.resize(&buf, &mut dst)?;
            ImgVec::new(dst, width, height)
        } else {
            image.into_owned()
        };

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
        Ok(image)
    }
}

/// add_frame is going to resize the image to this size.
/// The `Option` args are user-specified max width and max height
fn dimensions_for_image((img_w, img_h): (usize, usize), resize_to: (Option<u32>, Option<u32>)) -> (usize, usize) {
    match resize_to {
        (None, None) => {
            let factor = (img_w * img_h + 800 * 600) / (800 * 600);
            if factor > 1 {
                (img_w / factor, img_h / factor)
            } else {
                (img_w, img_h)
            }
        },
        (Some(w), Some(h)) => {
            ((w as usize).min(img_w), (h as usize).min(img_h))
        },
        (Some(w), None) => {
            let w = (w as usize).min(img_w);
            (w, img_h * w / img_w)
        }
        (None, Some(h)) => {
            let h = (h as usize).min(img_h);
            (img_w * h / img_h, h)
        },
    }
}

/// Encode collected frames
impl Writer {
    /// `importance_map` is computed from previous and next frame.
    /// Improves quality of pixels visible for longer.
    /// Avoids wasting palette on pixels identical to the background.
    ///
    /// `background` is the previous frame.
    fn quantize(image: ImgRef<'_, RGBA8>, importance_map: &[u8], has_prev_frame: bool, settings: &Settings) -> CatResult<(Attributes, QuantizationResult, Image<'static>)> {
        let mut liq = Attributes::new();
        if settings.fast {
            liq.set_speed(10);
        }
        let quality = if has_prev_frame {
            settings.color_quality().into()
        } else {
            100 // the first frame is too important to ruin it
        };
        liq.set_quality(0, quality);
        let mut img = liq.new_image_stride_copy(image.buf(), image.width(), image.height(), image.stride(), 0.)?;
        img.set_importance_map(importance_map)?;
        if has_prev_frame {
            img.add_fixed_color(RGBA8::new(0, 0, 0, 0));
        }
        let res = liq.quantize(&img)?;
        Ok((liq, res, img))
    }

    fn remap(liq: Attributes, mut res: QuantizationResult, mut img: Image<'static>, background: Option<ImgRef<'_, RGBA8>>, settings: &Settings) -> CatResult<(ImgVec<u8>, Vec<RGBA8>)> {
        if let Some(bg) = background {
            img.set_background(liq.new_image_stride(bg.buf(), bg.width(), bg.height(), bg.stride(), 0.)?)?;
        }

        res.set_dithering_level((settings.quality as f32 / 50.0 - 1.).max(0.));

        let (pal, pal_img) = res.remapped(&mut img)?;
        debug_assert_eq!(img.width() * img.height(), pal_img.len());

        Ok((Img::new(pal_img, img.width(), img.height()), pal))
    }

    fn write_frames(write_queue: Receiver<FrameMessage>, enc: &mut dyn Encoder, settings: &Settings, reporter: &mut dyn ProgressReporter) -> CatResult<()> {
        let mut pts_in_delay_units = 0_u64;

        let mut n_done = 0;
        for FrameMessage {frame, ordinal_frame_number, end_pts, ..} in write_queue {
            let delay = ((end_pts * 100.0).round() as u64)
                .saturating_sub(pts_in_delay_units)
                .min(30000) as u16;
            pts_in_delay_units += u64::from(delay);

            debug_assert_ne!(0, delay);

            // skip frames with bad pts
            if delay != 0 {
                enc.write_frame(frame, delay, settings)?;
            }

            // loop to report skipped frames too
            while n_done < ordinal_frame_number {
                n_done += 1;
                if !reporter.increase() {
                    return Err(Error::Aborted);
                }
            }
        }
        if n_done == 0 {
            return Err(Error::NoFrames);
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
            if self.settings.quality < 100 {
                let mut gifsicle = encodegifsicle::Gifsicle::new(self.settings.gifsicle_loss(), &mut writer);
                return self.write_with_encoder(&mut gifsicle, reporter);
            }
        }
        self.write_with_encoder(&mut encoderust::RustEncoder::new(writer), reporter)
    }

    fn write_with_encoder(mut self, encoder: &mut dyn Encoder, reporter: &mut dyn ProgressReporter) -> CatResult<()> {
        let decode_queue_recv = self.queue_iter.take().ok_or(Error::Aborted)?;

        let settings = self.settings;
        let (quant_queue, quant_queue_recv) = crossbeam_channel::bounded(4);
        let diff_thread = thread::Builder::new().name("diff".into()).spawn(move || {
            Self::make_diffs(decode_queue_recv, quant_queue, &settings)
        })?;
        let (remap_queue, remap_queue_recv) = crossbeam_channel::bounded(8);
        let quant_thread = thread::Builder::new().name("quant".into()).spawn(move || {
            Self::quantize_frames(quant_queue_recv, remap_queue, &settings)
        })?;
        let (write_queue, write_queue_recv) = crossbeam_channel::bounded(6);
        let remap_thread = thread::Builder::new().name("remap".into()).spawn(move || {
            Self::remap_frames(remap_queue_recv, write_queue, &settings)
        })?;
        Self::write_frames(write_queue_recv, encoder, &self.settings, reporter)?;
        diff_thread.join().map_err(|_| Error::ThreadSend)??;
        quant_thread.join().map_err(|_| Error::ThreadSend)??;
        remap_thread.join().map_err(|_| Error::ThreadSend)??;
        Ok(())
    }

    fn make_diffs(mut inputs: OrdQueueIter<DecodedImage>, quant_queue: Sender<DiffMessage>, settings: &Settings) -> CatResult<()> {
        let (first_frame, first_frame_pts) = inputs.next().transpose()?.ok_or(Error::NoFrames)?;
        let mut prev_frame_pts = -1.0;

        let mut denoiser = Denoiser::new(first_frame.width(), first_frame.height(), settings.quality);

        let first_frame_has_transparency = first_frame.pixels().any(|px| px.a < 128);

        let mut next_frame = Some((first_frame, first_frame_pts));
        let mut ordinal_frame_number = 0;
        loop {
            // NB! There are two interleaved loops here:
            //  - one to feed the denoiser
            //  - the other to process denoised frames
            //
            // The denoiser buffers five frames, so these two loops process different frames!
            // But need to be interleaved in one `loop{}` to get frames falling out of denoiser's buffer.

            ////////////////////// Feed denoiser: /////////////////////

            let curr_frame = next_frame.take();
            next_frame = inputs.next().transpose()?;

            if let Some((image, mut pts)) = curr_frame {
                pts -= first_frame_pts;
                ordinal_frame_number += 1;

                let dispose = if let Some((next, _)) = &next_frame {
                    if next.width() != image.width() || next.height() != image.height() {
                        return Err(Error::WrongSize(format!("Frame {} has wrong size ({}×{}, expected {}×{})", ordinal_frame_number,
                            next.width(), next.height(), image.width(), image.height())));
                    }

                    // Skip identical frames
                    if next.as_ref() == image.as_ref() {
                        prev_frame_pts = pts;
                        continue;
                    }

                    // If the next frame becomes transparent, this frame has to clear to bg for it
                    if next.pixels().zip(image.pixels()).any(|(next, curr)| next.a < curr.a) {
                        gif::DisposalMethod::Background
                    } else {
                        gif::DisposalMethod::Keep
                    }
                } else {
                    if first_frame_has_transparency {
                        // Last frame should reset to background to avoid breaking transparent looped anims
                        gif::DisposalMethod::Background
                    } else {
                        // macOS preview gets Background wrong
                        gif::DisposalMethod::Keep
                    }
                };

                // conversion from pts to delay
                let end_pts = if let Some((_, next_pts)) = next_frame {
                    next_pts - first_frame_pts
                } else if first_frame_pts > 1. / 100. {
                    // this is gifski's weird rule that non-zero first-frame pts
                    // shifts the whole anim and is the delay of the last frame
                    pts + first_frame_pts
                } else {
                    // otherwise assume steady framerate
                    pts + (pts - prev_frame_pts)
                };
                debug_assert!(end_pts > 0.);
                prev_frame_pts = pts;

                denoiser.push_frame(image.as_ref(), (ordinal_frame_number, end_pts, dispose));
                if next_frame.is_none() {
                    denoiser.flush();
                }
            }

            ////////////////////// Consume denoised frames /////////////////////

            let (importance_map, image, (ordinal_frame_number, end_pts, dispose)) = match denoiser.pop() {
                Denoised::Done => {
                    debug_assert!(next_frame.is_none());
                    break
                },
                Denoised::NotYet => continue,
                Denoised::Frame { importance_map, frame, meta } => ( importance_map, frame, meta ),
            };

            let (importance_map, ..) = importance_map.into_contiguous_buf();

            quant_queue.send(DiffMessage {
                dispose,
                importance_map,
                ordinal_frame_number,
                image,
                end_pts,
            })?;
        }

        Ok(())
    }

    fn quantize_frames(inputs: Receiver<DiffMessage>, remap_queue: Sender<RemapMessage>, settings: &Settings) -> CatResult<()> {
        let mut prev_frame_keeps = false;
        while let Some(DiffMessage {image, end_pts, dispose, ordinal_frame_number, mut importance_map}) = inputs.recv().ok() {
            if !prev_frame_keeps || importance_map.iter().any(|&px| px > 0) {
                let (liq, remap, liq_image) = Self::quantize(image.as_ref(), &importance_map, ordinal_frame_number > 1, settings)?;
                let max_loss = settings.gifsicle_loss();
                for imp in &mut importance_map {
                    // encoding assumes rgba background looks like encoded background, which is not true for lossy
                    *imp = ((256 - (*imp) as u32) * max_loss / 256).min(255) as u8;
                }
                remap_queue.send(RemapMessage {
                    ordinal_frame_number,
                    end_pts,
                    dispose,
                    liq, remap,
                    liq_image,
                })?;
            }
            prev_frame_keeps = dispose == gif::DisposalMethod::Keep;
        }
        Ok(())
    }

    fn remap_frames(inputs: Receiver<RemapMessage>, write_queue: Sender<FrameMessage>, settings: &Settings) -> CatResult<()> {
        let next_frame = inputs.recv().map_err(|_| Error::NoFrames)?;
        let mut screen = gif_dispose::Screen::new(next_frame.liq_image.width(), next_frame.liq_image.height(), RGBA8::new(0, 0, 0, 0), None);

        let mut next_frame = Some(next_frame);

        let mut first_frame = true;
        while let Some(RemapMessage {ordinal_frame_number, end_pts, dispose, liq, remap, liq_image}) = {
            // that's not the while loop, that block gets the next element
            let curr_frame = next_frame.take();
            next_frame = inputs.recv().ok();
            curr_frame
        } {
            let screen_width = screen.pixels.width() as u16;
            let screen_height = screen.pixels.height() as u16;
            let mut screen_after_dispose = screen.dispose();

            let (mut image8, mut image8_pal) = {
                let bg = if !first_frame { Some(screen_after_dispose.pixels()) } else { None };
                Self::remap(liq, remap, liq_image, bg, settings)?
            };

            // Palette may have multiple transparent indices :(
            let mut transparent_index = None;
            for (i, p) in image8_pal.iter_mut().enumerate() {
                if p.a <= 128 {
                    p.a = 0;
                    let new_index = i as u8;
                    if let Some(old_index) = transparent_index {
                        image8.pixels_mut().filter(|px| **px == new_index).for_each(|px| *px = old_index);
                    } else {
                        transparent_index = Some(new_index);
                    }
                }
            }

            // Check that palette is fine and has no duplicate transparent indices
            debug_assert!(image8_pal.iter().enumerate().all(|(idx, color)| {
                Some(idx as u8) == transparent_index || color.a > 128 || !image8.pixels().any(|px| px == idx as u8)
            }));

            let (left, top, image8) = if !first_frame && next_frame.is_some() {
                match trim_image(image8, &image8_pal, transparent_index, screen_after_dispose.pixels()) {
                    Some(trimmed) => trimmed,
                    None => continue, // no pixels left
                }
            } else {
                // must keep first and last frame
                (0, 0, image8)
            };

            screen_after_dispose.then_blit(Some(&image8_pal), dispose, left, top as _, image8.as_ref(), transparent_index)?;

            let frame = GIFFrame {
                left,
                top,
                screen_width,
                screen_height,
                image: image8,
                pal: image8_pal,
                transparent_index,
                dispose,
            };

            write_queue.send(FrameMessage {
                ordinal_frame_number,
                end_pts,
                frame,
            })?;

            first_frame = false;
        }
        Ok(())
    }
}

fn trim_image(mut image8: ImgVec<u8>, image8_pal: &[RGBA8], transparent_index: Option<u8>, screen: ImgRef<RGBA8>) -> Option<(u16, u16, ImgVec<u8>)> {
    let mut image_trimmed = image8.as_ref();

    let bottom = image_trimmed.rows().zip(screen.rows()).rev()
        .take_while(|(img_row, screen_row)| {
            img_row.iter().copied().zip(screen_row.iter().copied())
                .all(|(px, bg)| {
                    Some(px) == transparent_index || image8_pal.get(px as usize) == Some(&bg)
                })
        })
        .count();

    if bottom > 0 {
        if bottom == image_trimmed.height() {
            return None;
        }
        image_trimmed = image_trimmed.sub_image(0, 0, image_trimmed.width(), image_trimmed.height() - bottom);
    }

    let top = image_trimmed.rows().zip(screen.rows())
        .take_while(|(img_row, screen_row)| {
            img_row.iter().copied().zip(screen_row.iter().copied())
                .all(|(px, bg)| {
                    Some(px) == transparent_index || image8_pal.get(px as usize) == Some(&bg)
                })
        })
        .count();

    if top > 0 {
        image_trimmed = image_trimmed.sub_image(0, top, image_trimmed.width(), image_trimmed.height() - top);
    }

    if image_trimmed.height() != image8.height() {
        let (buf, width, height) = image_trimmed.to_contiguous_buf();
        image8 = Img::new(buf.into_owned(), width, height);
    }

    Some((0, top as _, image8))
}
