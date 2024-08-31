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
//! gif.ski library allows creation of GIF animations from [arbitrary pixels][ImgVec],
//! or [PNG files][Collector::add_frame_png_file].
//!
//! See the [`new`] function to get started.
#![doc(html_logo_url = "https://gif.ski/icon.png")]
#![allow(clippy::bool_to_int_with_if)]
#![allow(clippy::cast_possible_truncation)]
#![allow(clippy::enum_glob_use)]
#![allow(clippy::if_not_else)]
#![allow(clippy::inline_always)]
#![allow(clippy::match_same_arms)]
#![allow(clippy::missing_errors_doc)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::needless_pass_by_value)]
#![allow(clippy::redundant_closure_for_method_calls)]
#![allow(clippy::wildcard_imports)]

use encoderust::RustEncoder;
use gif::DisposalMethod;
use imagequant::{Image, QuantizationResult, Attributes};
use imgref::*;
use rgb::*;

mod error;
pub use crate::error::*;
use ordered_channel::Sender as OrdQueue;
use ordered_channel::Receiver as OrdQueueIter;
use ordered_channel::bounded as ordqueue_new;
pub mod progress;
use crate::progress::*;
pub mod c_api;
mod denoise;
use crate::denoise::*;
mod encoderust;
pub mod collector;
use crate::collector::{InputFrameResized, InputFrame, FrameSource};
#[doc(inline)]
pub use crate::collector::Collector;

#[cfg(feature = "gifsicle")]
mod gifsicle;

mod minipool;

use crossbeam_channel::{Receiver, Sender};
use std::cell::Cell;
use std::io::prelude::*;
use std::num::NonZeroU8;
use std::rc::Rc;
use std::thread;
use std::sync::atomic::Ordering::Relaxed;


/// Number of repetitions
pub type Repeat = gif::Repeat;

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

#[derive(Copy, Clone)]
#[non_exhaustive]
struct SettingsExt {
    pub s: Settings,
    pub max_threads: NonZeroU8,
    pub extra_effort: bool,
    pub motion_quality: u8,
    pub giflossy_quality: u8,
    pub matte: Option<RGB8>,
}

impl Settings {
    /// quality is used in other places, like gifsicle or frame differences,
    /// and it's better to lower quality there before ruining quantization
    pub(crate) fn color_quality(&self) -> u8 {
        (u16::from(self.quality) * 4 / 3).min(100) as u8
    }

    /// `add_frame` is going to resize the images to this size.
    #[must_use]
    #[inline]
    pub fn dimensions_for_image(&self, width: usize, height: usize) -> (usize, usize) {
        dimensions_for_image((width, height), (self.width, self.height))
    }
}

impl SettingsExt {
    pub(crate) fn gifsicle_loss(&self) -> u32 {
        if cfg!(feature = "gifsicle") && self.giflossy_quality < 100 {
            ((100. / 5. - f32::from(self.giflossy_quality) / 5.).powf(1.8).ceil() as u32 + 10) * 10
        } else {
            0
        }
    }

    pub(crate) fn dithering_level(&self) -> f32 {
        let gifsicle_quality = if cfg!(feature = "gifsicle") { self.giflossy_quality } else { 100 };
        debug_assert!(gifsicle_quality <= 100);
        // lossy LZW adds its own dithering, so the input could be less nosiy to compensate
        // but don't change dithering unless gifsicle quality < 90, and don't completely disable it
        let gifsicle_factor = 0.25 + f32::from(gifsicle_quality) * (1./100. * 1./0.9 * 0.75);

        (f32::from(self.s.quality) * (1./50. * gifsicle_factor) - 1.).clamp(0.2, 1.)
    }
}

impl Default for Settings {
    #[inline]
    fn default() -> Self {
        Self {
            width: None, height: None,
            quality: 100,
            fast: false,
            repeat: Repeat::Infinite,
        }
    }
}

/// Perform GIF writing
pub struct Writer {
    /// Input frame decoder results
    queue_iter: Option<Receiver<InputFrame>>,
    settings: SettingsExt,
    /// Colors the caller has specified as fixed (i.e. key colours)
    /// This can't be in settings because that would cause it to lose Copy.
    /// Additionally to avoid breaking C API compatibility this has to be mutable there too.
    fixed_colors: Vec<RGB8>,
}

struct GIFFrame {
    left: u16,
    top: u16,
    image: ImgVec<u8>,
    pal: Vec<RGB8>,
    dispose: DisposalMethod,
    transparent_index: Option<u8>,
}

/// Frame before quantization
struct DiffMessage {
    /// 1..
    ordinal_frame_number: usize,
    pts: f64, frame_duration: f64,
    image: ImgVec<RGBA8>,
    importance_map: Vec<u8>,
}

struct QuantizeMessage {
    /// 1.. with holes
    ordinal_frame_number: usize,
    /// 0.. no holes
    frame_index: u32,
    first_frame_has_transparency: bool,
    image: ImgVec<RGBA8>,
    importance_map: Vec<u8>,
    prev_frame_keeps: bool,
    dispose: gif::DisposalMethod,
    end_pts: f64,
    has_next_frame: bool,
}

/// Frame post quantization, before remap
struct RemapMessage {
    /// 1..
    ordinal_frame_number: usize,
    end_pts: f64,
    dispose: DisposalMethod,
    liq: Attributes,
    remap: QuantizationResult,
    liq_image: Image<'static>,
    out_buf: Vec<u8>,
    has_next_frame: bool,
}

/// Frame post quantization and remap
struct FrameMessage {
    /// 0..
    frame_index: usize,
    /// 1..
    ordinal_frame_number: usize,
    end_pts: f64,
    frame: GIFFrame,
    screen_width: u16,
    screen_height: u16,
}

/// Start new encoding on two threads.
///
/// Encoding is always multi-threaded, and the `Collector` and `Writer`
/// must be used on sepate threads.
///
/// You feed input frames to the [`Collector`], and ask the [`Writer`] to
/// start writing the GIF.
///
/// If you don't start writing, then adding frames will block forever.
///
///
/// ```rust,no_run
/// use gifski::*;
///
/// let (collector, writer) = gifski::new(Settings::default())?;
/// std::thread::scope(|t| -> Result<(), Error> {
///     let frames_thread = t.spawn(move || {
///         for i in 0..10 {
///             collector.add_frame_png_file(i, format!("frame{i:04}.png").into(), i as f64 * 0.1)?;
///         }
///         drop(collector);
///         Ok(())
///     });
///
///     writer.write(std::fs::File::create("demo.gif")?, &mut progress::NoProgress{})?;
///     frames_thread.join().unwrap()
/// })?;
/// Ok::<_, Error>(())
/// ```
#[inline]
pub fn new(settings: Settings) -> GifResult<(Collector, Writer)> {
    if settings.quality == 0 || settings.quality > 100 {
        return Err(Error::WrongSize("quality must be 1-100".into())); // I forgot to add a better error variant
    }
    if settings.width.unwrap_or(0) > 1<<16 || settings.height.unwrap_or(0) > 1<<16 {
        return Err(Error::WrongSize("image size too large".into()));
    }

    let max_threads = thread::available_parallelism().map(|t| t.get().min(255) as u8).unwrap_or(8);
    let (queue, queue_iter) = crossbeam_channel::bounded(5.min(max_threads.into())); // should be sufficient for denoiser lookahead
    Ok((
        Collector {
            queue,
        },
        Writer {
            queue_iter: Some(queue_iter),
            settings: SettingsExt {
                s: settings,
                max_threads: max_threads.try_into()?,
                motion_quality: settings.quality,
                giflossy_quality: settings.quality,
                extra_effort: false,
                matte: None,
            },
            fixed_colors: Vec::new(),
        },
    ))
}

#[inline(never)]
#[cfg_attr(debug_assertions, track_caller)]
fn resized_binary_alpha(image: ImgVec<RGBA8>, width: Option<u32>, height: Option<u32>, matte: Option<RGB8>) -> CatResult<ImgVec<RGBA8>> {
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
        image
    };

    if let Some(matte) = matte {
        image.pixels_mut().filter(|px| px.a < 255 && px.a > 0).for_each(move |px| {
            let alpha = u16::from(px.a);
            let inv_alpha = 255 - alpha;

            *px = RGBA8 {
                r: ((u16::from(px.r) * alpha + u16::from(matte.r) * inv_alpha) / 255) as u8,
                g: ((u16::from(px.g) * alpha + u16::from(matte.g) * inv_alpha) / 255) as u8,
                b: ((u16::from(px.b) * alpha + u16::from(matte.b) * inv_alpha) / 255) as u8,
                a: 255,
            };
        });
    } else {
        dither_image(image.as_mut());
    }

    Ok(image)
}

#[allow(clippy::identity_op)]
#[allow(clippy::erasing_op)]
#[inline(never)]
fn dither_image(mut image: ImgRefMut<RGBA8>) {
    let width = image.width();
    let height = image.height();

    // dithering of anti-aliased edges can look very fuzzy, so disable it near the edges
    let mut anti_aliasing = vec![false; width * height];
    loop9::loop9(image.as_ref(), 0, 0, width, height, |x,y, top, mid, bot| {
        if mid.curr.a != 255 && mid.curr.a != 0 {
            fn is_edge(a: u8, b: u8) -> bool {
                a < 12 && b >= 240 ||
                b < 12 && a >= 240
            }
            if is_edge(top.curr.a, bot.curr.a) ||
            is_edge(mid.prev.a, mid.next.a) ||
            is_edge(top.prev.a, bot.next.a) ||
            is_edge(top.next.a, bot.prev.a) {
                anti_aliasing[x + y * width] = true;
            }
        }
    });

    // this table is already biased, so that px.a doesn't need to be changed
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
    for (y, (row, aa)) in image.rows_mut().zip(anti_aliasing.chunks_exact(width)).enumerate() {
        for (x, (px, aa)) in row.iter_mut().zip(aa.iter().copied()).enumerate() {
            if px.a < 255 {
                if aa {
                    px.a = if px.a < 89 { 0 } else { 255 };
                } else {
                    px.a = if px.a < DITHER[(y & 7) * 8 + (x & 7)] { 0 } else { 255 };
                }
            }
        }
    }
}

/// `add_frame` is going to resize the image to this size.
/// The `Option` args are user-specified max width and max height
#[inline(never)]
fn dimensions_for_image((img_w, img_h): (usize, usize), resize_to: (Option<u32>, Option<u32>)) -> (usize, usize) {
    match resize_to {
        (None, None) => {
            let factor = ((img_w * img_h + 800 * 600 / 2) as f64 / f64::from(800 * 600)).sqrt().round() as usize;
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

#[derive(Copy, Clone)]
enum LastFrameDuration {
    FixedOffset(f64),
    FrameRate(f64),
}

impl LastFrameDuration {
    #[inline]
    pub fn value(&self) -> f64 {
        match self {
            Self::FixedOffset(val) | Self::FrameRate(val) => *val,
        }
    }

    #[inline]
    pub fn shift_every_pts_by(&self) -> f64 {
        match self {
            Self::FixedOffset(offset) => *offset,
            Self::FrameRate(_) => 0.,
        }
    }
}

/// Encode collected frames
impl Writer {
    #[deprecated(note = "please don't use, it will be in Settings eventually")]
    #[doc(hidden)]
    pub fn set_extra_effort(&mut self, enabled: bool) {
        self.settings.extra_effort = enabled;
    }

    #[deprecated(note = "please don't use, it will be in Settings eventually")]
    #[doc(hidden)]
    pub fn set_motion_quality(&mut self, q: u8) {
        self.settings.motion_quality = q;
    }

    #[deprecated(note = "please don't use, it will be in Settings eventually")]
    #[doc(hidden)]
    pub fn set_lossy_quality(&mut self, q: u8) {
        self.settings.giflossy_quality = q;
    }

    /// Adds a fixed color that will be kept in the palette at all times.
    ///
    /// This may increase file size, because every frame will use a larger palette.
    /// Max 255 allowed, because one more is reserved for transparency.
    pub fn add_fixed_color(&mut self, col: RGB8) {
        if self.fixed_colors.len() < 255 {
            self.fixed_colors.push(col);
        }
    }

    #[deprecated(note = "please don't use, it will be in Settings eventually")]
    #[doc(hidden)]
    pub fn set_matte_color(&mut self, col: RGB8) {
        self.settings.matte = Some(col);
    }

    /// `importance_map` is computed from previous and next frame.
    /// Improves quality of pixels visible for longer.
    /// Avoids wasting palette on pixels identical to the background.
    ///
    /// `background` is the previous frame.
    fn quantize(&self, image: ImgVec<RGBA8>, importance_map: &[u8], first_frame: bool, needs_transparency: bool, prev_frame_keeps: bool) -> CatResult<(Attributes, QuantizationResult, Image<'static>, Vec<u8>)> {
        let mut liq = Attributes::new();
        if self.settings.s.fast && !first_frame {
            liq.set_speed(10)?;
        } else if self.settings.extra_effort {
            liq.set_speed(1)?;
        }
        let quality = if !first_frame {
            self.settings.s.color_quality()
        } else {
            100 // the first frame is too important to ruin it
        };
        liq.set_quality(0, quality)?;
        if self.settings.s.quality < 50 {
            let min_colors = 5 + self.fixed_colors.len() as u32;
            liq.set_max_colors(u32::from(self.settings.s.quality * 2).max(min_colors).next_power_of_two().min(256))?;
        }
        let (buf, width, height) = image.into_contiguous_buf();
        let mut img = liq.new_image(buf, width, height, 0.)?;
        // only later remapping tracks which area has been damaged by transparency
        // so for previous-transparent background frame the importance map may be invalid
        // because there's a transparent hole in the background not taken into account,
        // and palette may lack colors to fill that hole
        if first_frame || prev_frame_keeps {
            img.set_importance_map(importance_map)?;
        }
        // first frame may be transparent too, so it's not just for diffs
        if needs_transparency {
            img.add_fixed_color(RGBA8::new(0, 0, 0, 0))?;
        }
        // user may have colors which need to be preserved and left undithered
        for color in &self.fixed_colors {
            img.add_fixed_color(RGBA8::new(color.r, color.g, color.b, 255))?;
        }

        let mut res = liq.quantize(&mut img)?;

        // GIF only stores power-of-two palette sizes
        if self.settings.extra_effort {
            let len = res.palette_len();
            // it has little impact on compression (128c -> 64c is only 7% smaller)
            if (len < 128 || len > 220) && len != len.next_power_of_two() {
                liq.set_max_colors(len.next_power_of_two() as _)?;
                liq.set_quality(0, 100)?;
                res = liq.quantize(&mut img)?;
            }
        }
        res.set_dithering_level(self.settings.dithering_level())?;

        let mut out = Vec::new();
        out.try_reserve_exact(width*height).map_err(imagequant::liq_error::from)?;
        res.optionally_prepare_for_dithering_with_background_set(&mut img, &mut out.spare_capacity_mut()[..width*height])?;

        Ok((liq, res, img, out))
    }

    fn remap<'a>(&self, liq: Attributes, mut res: QuantizationResult, mut img: Image<'a>, background: Option<ImgRef<'a, RGBA8>>, mut pal_img: Vec<u8>) -> CatResult<(ImgVec<u8>, Vec<RGBA8>)> {
        if let Some(bg) = background {
            img.set_background(Image::new_stride_borrowed(&liq, bg.buf(), bg.width(), bg.height(), bg.stride(), 0.)?)?;
        }

        let pal = res.remap_into_vec(&mut img, &mut pal_img)?;
        debug_assert_eq!(img.width() * img.height(), pal_img.len());

        Ok((Img::new(pal_img, img.width(), img.height()), pal))
    }

    #[inline(never)]
    fn write_frames(&self, write_queue: Receiver<FrameMessage>, writer: &mut dyn Write, reporter: &mut dyn ProgressReporter) -> CatResult<()> {
        let (lzw_queue, lzw_recv) = ordqueue_new(2);
        minipool::new_scope((if self.settings.s.fast || self.settings.gifsicle_loss() > 0 { 3 } else { 1 }).try_into().unwrap(), "lzw", move || {
            let mut pts_in_delay_units = 0_u64;

            let written = Rc::new(Cell::new(0));
            let mut enc = RustEncoder::new(writer, written.clone());

            let mut n_done = 0;
            for tmp in lzw_recv {
                let (end_pts, ordinal_frame_number, frame, screen_width, screen_height): (f64, _, _, _, _) = tmp;
                // delay=1 doesn't work, and it's too late to drop frames now
                let delay = ((end_pts * 100_f64).round() as u64)
                    .saturating_sub(pts_in_delay_units)
                    .clamp(2, 30000) as u16;
                pts_in_delay_units += u64::from(delay);

                enc.write_frame(frame, delay, screen_width, screen_height, &self.settings.s)?;

                reporter.written_bytes(written.get());

                // loop to report skipped frames too
                while n_done < ordinal_frame_number {
                    n_done += 1;
                    if !reporter.increase() {
                        return Err(Error::Aborted);
                    }
                }
            }
            if n_done == 0 {
                Err(Error::NoFrames)
            } else {
                Ok(())
            }
        }, move |abort| {
            for FrameMessage {frame, frame_index, ordinal_frame_number, end_pts, screen_width, screen_height } in write_queue {
                if abort.load(Relaxed) {
                    return Err(Error::Aborted);
                }

                let frame = RustEncoder::<&mut dyn std::io::Write>::compress_frame(frame, &self.settings)?;
                lzw_queue.send(frame_index, (end_pts, ordinal_frame_number, frame, screen_width, screen_height))?;
            }
            Ok(())
        })
    }

    /// Start writing frames. This function will not return until the [`Collector`] is dropped.
    ///
    /// `outfile` can be any writer, such as `File` or `&mut Vec`.
    ///
    /// `ProgressReporter.increase()` is called each time a new frame is being written.
    #[inline]
    pub fn write<W: Write>(mut self, mut writer: W, reporter: &mut dyn ProgressReporter) -> GifResult<()> {
        let decode_queue_recv = self.queue_iter.take().ok_or(Error::Aborted)?;
        self.write_inner(decode_queue_recv, &mut writer, reporter)
    }

    #[inline(never)]
    fn write_inner(&self, decode_queue_recv: Receiver<InputFrame>, writer: &mut dyn Write, reporter: &mut dyn ProgressReporter) -> CatResult<()> {
        thread::scope(|s| {
            let (diff_queue, diff_queue_recv) = ordqueue_new(0);
            let resize_thread = thread::Builder::new().name("resize".into()).spawn_scoped(s, move || {
                self.make_resize(decode_queue_recv, diff_queue)
            })?;
            let (quant_queue, quant_queue_recv) = crossbeam_channel::bounded(0);
            let diff_thread = thread::Builder::new().name("diff".into()).spawn_scoped(s, move || {
                self.make_diffs(diff_queue_recv, quant_queue)
            })?;
            let (remap_queue, remap_queue_recv) = ordqueue_new(0);
            let quant_thread = thread::Builder::new().name("quant".into()).spawn_scoped(s, move || {
                self.quantize_frames(quant_queue_recv, remap_queue)
            })?;
            let (write_queue, write_queue_recv) = crossbeam_channel::bounded(0);
            let remap_thread = thread::Builder::new().name("remap".into()).spawn_scoped(s, move || {
                self.remap_frames(remap_queue_recv, write_queue)
            })?;
            let res0 = self.write_frames(write_queue_recv, writer, reporter);
            let res1 = resize_thread.join().map_err(handle_join_error)?;
            let res2 = diff_thread.join().map_err(handle_join_error)?;
            let res3 = quant_thread.join().map_err(handle_join_error)?;
            let res4 = remap_thread.join().map_err(handle_join_error)?;
            combine_res(combine_res(combine_res(res0, res1), combine_res(res2, res3)), res4)
        })
    }

    /// Apply resizing and crate a blurred version for the diff/denoise phase
    fn make_resize(&self, inputs: Receiver<InputFrame>, diff_queue: OrdQueue<InputFrameResized>) -> CatResult<()> {
        minipool::new_scope(self.settings.max_threads.min(if self.settings.s.fast || self.settings.extra_effort { 6 } else { 4 }.try_into()?), "resize", move || {
            Ok(())
        }, move |abort| {
            for frame in inputs {
                if abort.load(Relaxed) {
                    return Err(Error::Aborted);
                }
                let image = match frame.frame {
                    FrameSource::Pixels(image) => image,
                    #[cfg(feature = "png")]
                    FrameSource::PngData(data) => {
                        let image = lodepng::decode32(&data)
                            .map_err(|err| Error::PNG(format!("Can't load PNG: {err}")))?;
                        Img::new(image.buffer, image.width, image.height)
                    },
                    #[cfg(feature = "png")]
                    FrameSource::Path(path) => {
                        let image = lodepng::decode32_file(&path)
                            .map_err(|err| Error::PNG(format!("Can't load {}: {err}", path.display())))?;
                        Img::new(image.buffer, image.width, image.height)
                    },
                };
                let resized = resized_binary_alpha(image, self.settings.s.width, self.settings.s.height, self.settings.matte)?;
                let frame_blurred = if self.settings.extra_effort { smart_blur(resized.as_ref()) } else { less_smart_blur(resized.as_ref()) };
                diff_queue.send(frame.frame_index, InputFrameResized {
                    frame: resized,
                    frame_blurred,
                    presentation_timestamp: frame.presentation_timestamp,
                })?;
            }
            Ok(())
        })
    }

    /// Find differences between frames, and compute importance maps
    fn make_diffs(&self, mut inputs: OrdQueueIter<InputFrameResized>, diffs: Sender<DiffMessage>) -> CatResult<()> {
        let first_frame = inputs.next().ok_or(Error::NoFrames)?;

        let mut last_frame_duration = if first_frame.presentation_timestamp > 1. / 100. {
            // this is gifski's weird rule that a non-zero first-frame pts
            // shifts the whole anim and is the delay of the last frame
            LastFrameDuration::FixedOffset(first_frame.presentation_timestamp)
        } else {
            LastFrameDuration::FrameRate(0.)
        };

        let mut denoiser = Denoiser::new(first_frame.frame.width(), first_frame.frame.height(), self.settings.motion_quality)?;

        let mut ordinal_frame_number = 0;
        let mut last_frame_pts = 0.;
        let mut next_frame = Some(first_frame);
        loop {
            // NB! There are two interleaved loops here:
            //  - one to feed the denoiser
            //  - the other to process denoised frames
            //
            // The denoiser buffers five frames, so these two loops process different frames!
            // But need to be interleaved in one `loop{}` to get frames falling out of denoiser's buffer.

            ////////////////////// Feed denoiser: /////////////////////

            if let Some(InputFrameResized { frame, frame_blurred, presentation_timestamp: raw_pts }) = next_frame {
                ordinal_frame_number += 1;

                let pts = raw_pts - last_frame_duration.shift_every_pts_by();
                if let LastFrameDuration::FrameRate(duration) = &mut last_frame_duration {
                    *duration = pts - last_frame_pts;
                }
                last_frame_pts = pts;

                denoiser.push_frame(frame.as_ref(), frame_blurred.as_ref(), (ordinal_frame_number, pts, last_frame_duration)).map_err(|_| {
                    Error::WrongSize(format!("Frame {ordinal_frame_number} has wrong size ({}×{})", frame.width(), frame.height()))
                })?;
            } else {
                denoiser.flush();
            }

            ////////////////////// Consume denoised frames /////////////////////

            match denoiser.pop() {
                Denoised::Done => {
                    debug_assert!(inputs.next().is_none());
                    break
                },
                Denoised::NotYet => {},
                Denoised::Frame { importance_map, frame: image, meta: (ordinal_frame_number, pts, last_frame_duration) } => {
                    let (importance_map, ..) = importance_map.into_contiguous_buf();
                    diffs.send(DiffMessage {
                        importance_map,
                        ordinal_frame_number,
                        image,
                        pts, frame_duration: last_frame_duration.value().max(1. / 100.),
                    })?;
                },
            };
            next_frame = inputs.next();
        }

        Ok(())
    }

    fn quantize_frames(&self, inputs: Receiver<DiffMessage>, remap_queue: OrdQueue<RemapMessage>) -> CatResult<()> {
        minipool::new_channel(self.settings.max_threads.min(4.try_into()?), "quant", move |quant_queue| {
        let mut inputs = inputs.into_iter();
        let next_frame = inputs.next().ok_or(Error::NoFrames)?;

        let DiffMessage {image: first_frame, ..} = &next_frame;
        let first_frame_has_transparency = first_frame.pixels().any(|px| px.a < 128);

        let mut prev_frame_keeps = false;
        let mut frame_index = 0;
        let mut importance_map = None;
        let mut next_frame = Some(next_frame);
        while let Some(DiffMessage { image, pts, frame_duration, ordinal_frame_number, importance_map: new_importance_map }) = next_frame {
            next_frame = inputs.next();

            if importance_map.is_none() {
                importance_map = Some(new_importance_map);
            }

            let dispose = if let Some(DiffMessage { image: next_image, .. }) = &next_frame {
                // Skip identical frames
                if next_image.as_ref() == image.as_ref() {
                    // this keeps importance_map of the previous frame in the identical-frame series
                    // (important, because subsequent identical frames have all-zero importance_map and would be dropped too)
                    continue;
                }

                // If the next frame becomes transparent, this frame has to clear to bg for it
                if next_image.pixels().zip(image.pixels()).any(|(next, curr)| next.a < curr.a) {
                    DisposalMethod::Background
                } else {
                    DisposalMethod::Keep
                }
            } else if first_frame_has_transparency {
                // Last frame should reset to background to avoid breaking transparent looped anims
                DisposalMethod::Background
            } else {
                // macOS preview gets Background wrong
                DisposalMethod::Keep
            };

            let importance_map = importance_map.take().ok_or(Error::ThreadSend)?; // always set at the beginning

            if !prev_frame_keeps || importance_map.iter().any(|&px| px > 0) {
                let end_pts = if let Some(&DiffMessage { pts: next_pts, .. }) = next_frame.as_ref() {
                    next_pts
                } else {
                    pts + frame_duration
                };
                debug_assert!(end_pts > 0.);

                quant_queue.send(QuantizeMessage {
                    image,
                    ordinal_frame_number, frame_index,
                    first_frame_has_transparency,
                    importance_map, prev_frame_keeps, dispose, end_pts,
                    has_next_frame: next_frame.is_some(),
                })?;

                frame_index += 1;
                prev_frame_keeps = dispose == DisposalMethod::Keep;
            }
        }
        Ok(())
        }, move |QuantizeMessage { end_pts, mut image, importance_map, ordinal_frame_number, frame_index, dispose, first_frame_has_transparency, prev_frame_keeps, has_next_frame }| {
            if prev_frame_keeps {
                // if denoiser says the background didn't change, then believe it
                // (except higher quality settings, which try to improve it every time)
                let bg_keep_likelihood = u32::from(self.settings.s.quality.saturating_sub(80) / 4);
                if self.settings.s.fast || (self.settings.s.quality < 100 && (frame_index % 5) >= bg_keep_likelihood) {
                    image.pixels_mut().zip(&importance_map).filter(|&(_, &m)| m == 0).for_each(|(px, _)| *px = RGBA8::new(0,0,0,0));
                }
            }

            let needs_transparency = frame_index > 0 || (frame_index == 0 && first_frame_has_transparency);
            let (liq, remap, liq_image, out_buf) = self.quantize(image, &importance_map, frame_index == 0, needs_transparency, prev_frame_keeps)?;

            Ok(remap_queue.send(frame_index as usize, RemapMessage {
                ordinal_frame_number,
                end_pts,
                dispose,
                liq, remap,
                liq_image,
                out_buf,
                has_next_frame,
            })?)
        })
    }

    fn remap_frames(&self, mut inputs: OrdQueueIter<RemapMessage>, write_queue: Sender<FrameMessage>) -> CatResult<()> {
        let mut frame_index = 0;
        let first_frame = inputs.next().ok_or(Error::NoFrames)?;
        let mut screen = gif_dispose::Screen::new(first_frame.liq_image.width(), first_frame.liq_image.height(), None);

        #[cfg(debug_assertions)]
        let mut debug_screen = gif_dispose::Screen::new(first_frame.liq_image.width(), first_frame.liq_image.height(), None);

        let mut next_frame = Some(first_frame);
        while let Some(RemapMessage {ordinal_frame_number, end_pts, dispose, liq, remap, liq_image, out_buf, has_next_frame}) = next_frame {
            let pixels = screen.pixels_rgba();
            let screen_width = pixels.width() as u16;
            let screen_height = pixels.height() as u16;
            let mut screen_after_dispose = screen.dispose_only();

            let (mut image8, image8_pal) = {
                let bg = if frame_index != 0 { Some(screen_after_dispose.pixels_rgba()) } else { None };
                self.remap(liq, remap, liq_image, bg, out_buf)?
            };

            let (image8_pal, transparent_index) = transparent_index_from_palette(image8_pal, image8.as_mut());

            #[cfg(debug_assertions)]
            debug_screen.blit(Some(&image8_pal), dispose, 0, 0, image8.as_ref(), transparent_index)?;

            let (left, top) = if frame_index != 0 && has_next_frame {
                let (left, top, new_width, new_height) = trim_image(image8.as_ref(), &image8_pal, transparent_index, dispose, screen_after_dispose.pixels_rgba())
                    .unwrap_or((0, 0, 1, 1));
                if new_width != image8.width() || new_height != image8.height() {
                    let new_buf = image8.sub_image(left.into(), top.into(), new_width, new_height).to_contiguous_buf().0.into_owned();
                    image8 = ImgVec::new(new_buf, new_width, new_height);
                }
                (left, top)
            } else {
                // must keep first and last frame
                (0, 0)
            };

            screen_after_dispose.then_blit(Some(&image8_pal), dispose, left, top, image8.as_ref(), transparent_index)?;

            #[cfg(debug_assertions)]
            debug_assert!(debug_screen.pixels_rgba() == screen.pixels_rgba(), "fr {ordinal_frame_number} {left}/{top} {}x{}", image8.width(), image8.height());

            write_queue.send(FrameMessage {
                frame_index,
                ordinal_frame_number,
                end_pts,
                screen_width,
                screen_height,
                frame: GIFFrame {
                    left,
                    top,
                    image: image8,
                    pal: image8_pal,
                    transparent_index,
                    dispose,
                },
            })?;
            frame_index += 1;
            next_frame = inputs.next();
        }
        Ok(())
    }
}

fn transparent_index_from_palette(mut image8_pal: Vec<RGBA8>, mut image8: ImgRefMut<u8>) -> (Vec<RGB8>, Option<u8>) {
    // Palette may have multiple transparent indices :(
    let mut transparent_index = None;
    for (i, p) in image8_pal.iter_mut().enumerate() {
        if p.a <= 128 {
            *p = RGBA8::new(71,80,76,0);
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

    (image8_pal.into_iter().map(|r| r.rgb()).collect(), transparent_index)
}

/// When one thread unexpectedly fails, all other threads fail with Aborted, but that Aborted isn't the relevant cause
#[inline]
fn combine_res(res1: Result<(), Error>, res2: Result<(), Error>) -> Result<(), Error> {
    use Error::*;
    match (res1, res2) {
        (Err(e), Ok(())) | (Ok(()), Err(e)) => Err(e),
        (Err(ThreadSend), res) | (res, Err(ThreadSend)) => res,
        (Err(Aborted), res) | (res, Err(Aborted)) => res,
        (Err(NoFrames), res) | (res, Err(NoFrames)) => res,
        (_, res2) => res2,
    }
}

fn trim_image(mut image_trimmed: ImgRef<u8>, image8_pal: &[RGB8], transparent_index: Option<u8>, dispose: DisposalMethod, mut screen: ImgRef<RGBA8>) -> Option<(u16, u16, usize, usize)> {
    debug_assert_eq!(image_trimmed.width(), screen.width());
    debug_assert_eq!(image_trimmed.height(), screen.height());

    let is_matching_pixel = move |px: u8, bg: RGBA8| -> bool {
        if Some(px) == transparent_index {
            if dispose == DisposalMethod::Keep {
                // if dispose == keep, then transparent pixels do nothing, so they can be cropped out
                true
            } else {
                debug_assert_eq!(dispose, DisposalMethod::Background);
                // if disposing to background, then transparent pixels paint transparency, so bg has to actually be transparent to match
                bg.a == 0
            }
        } else {
            let Some(pal_px) = image8_pal.get(px as usize) else {
                debug_assert!(false, "{px} > {}", image8_pal.len());
                return false
            };
            pal_px.with_alpha(255) == bg
        }
    };

    let bottom = image_trimmed.rows().zip(screen.rows()).rev()
        .take_while(|(img_row, screen_row)| {
            img_row.iter().copied().zip(screen_row.iter().copied())
                .all(|(px, bg)| is_matching_pixel(px, bg))
        })
        .count();

    if bottom > 0 {
        if bottom == image_trimmed.height() {
            return None;
        }
        image_trimmed = image_trimmed.sub_image(0, 0, image_trimmed.width(), image_trimmed.height() - bottom);
        screen = screen.sub_image(0, 0, screen.width(), screen.height() - bottom);
    }

    let top = image_trimmed.rows().zip(screen.rows())
        .take_while(|(img_row, screen_row)| {
            img_row.iter().copied().zip(screen_row.iter().copied())
                .all(|(px, bg)| is_matching_pixel(px, bg))
        })
        .count();

    if top > 0 {
        debug_assert_ne!(image_trimmed.height(), top);
        image_trimmed = image_trimmed.sub_image(0, top, image_trimmed.width(), image_trimmed.height() - top);
        screen = screen.sub_image(0, top, screen.width(), screen.height() - top);
    }

    let left = (0..image_trimmed.width()-1)
        .take_while(|&x| {
            (0..image_trimmed.height()).all(|y| {
                let px = image_trimmed[(x, y)];
                is_matching_pixel(px, screen[(x, y)])
            })
        }).count();
    if left > 0 {
        debug_assert!(image_trimmed.width() > left);
        image_trimmed = image_trimmed.sub_image(left, 0, image_trimmed.width() - left, image_trimmed.height());
        screen = screen.sub_image(left, 0, screen.width() - left, screen.height());
    }
    debug_assert_eq!(image_trimmed.width(), screen.width());
    debug_assert_eq!(image_trimmed.height(), screen.height());

    let right = (1..image_trimmed.width()).rev()
        .take_while(|&x| {
            (0..image_trimmed.height()).all(|y| {
                let px = image_trimmed[(x, y)];
                is_matching_pixel(px, screen[(x, y)])
            })
        }).count();
    if right > 0 {
        debug_assert!(image_trimmed.width() > right);
        image_trimmed = image_trimmed.sub_image(0, 0, image_trimmed.width() - right, image_trimmed.height());
    }

    Some((left as _, top as _, image_trimmed.width(), image_trimmed.height()))
}

trait PushInCapacity<T> {
    fn push_in_cap(&mut self, val: T);
}

impl<T> PushInCapacity<T> for Vec<T> {
    #[inline(always)]
    #[cfg_attr(debug_assertions, track_caller)]
    fn push_in_cap(&mut self, val: T) {
        debug_assert!(self.capacity() != self.len());
        if self.capacity() != self.len() {
            self.push(val);
        }
    }
}

#[cold]
fn handle_join_error(err: Box<dyn std::any::Any + Send>) -> Error {
    let msg = err.downcast_ref::<String>().map(|s| s.as_str())
    .or_else(|| err.downcast_ref::<&str>().copied()).unwrap_or("unknown panic");
    eprintln!("thread crashed (this is a bug): {msg}");
    Error::ThreadSend
}

#[test]
fn sendable() {
    fn is_send<T: Send>() {}
    is_send::<Collector>();
    is_send::<Writer>();
}
