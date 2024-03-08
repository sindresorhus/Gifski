use std::collections::VecDeque;
use crate::PushInCapacity;
pub use imgref::ImgRef;
use imgref::ImgVec;
use loop9::loop9_img;
use rgb::ComponentMap;
use rgb::RGB8;
pub use rgb::RGBA8;

const LOOKAHEAD: usize = 5;

#[derive(Debug, Default, Copy, Clone)]
struct Acc {
    r: [u8; LOOKAHEAD],
    g: [u8; LOOKAHEAD],
    b: [u8; LOOKAHEAD],
    blur: [RGB8; LOOKAHEAD],
    alpha_bits: u8,
    can_stay_for: u8,
    stayed_for: u8,
    bg_set: RGBA8,
}

impl Acc {
    /// Actual pixel + blurred pixel
    #[inline(always)]
    pub fn get(&self, idx: usize) -> Option<(RGB8, RGB8)> {
        if idx >= LOOKAHEAD {
            debug_assert!(idx < LOOKAHEAD);
            return None;
        }
        if self.alpha_bits & (1 << idx) == 0 {
            Some((
                RGB8::new(self.r[idx], self.g[idx], self.b[idx]),
                self.blur[idx],
            ))
        } else {
            None
        }
    }

    #[inline(always)]
    pub fn append(&mut self, val: RGBA8, val_blur: RGB8) {
        for n in 1..LOOKAHEAD {
            self.r[n - 1] = self.r[n];
            self.g[n - 1] = self.g[n];
            self.b[n - 1] = self.b[n];
            self.blur[n - 1] = self.blur[n];
        }
        self.alpha_bits >>= 1;

        if val.a < 128 {
            self.alpha_bits |= 1 << (LOOKAHEAD - 1);
        } else {
            self.r[LOOKAHEAD - 1] = val.r;
            self.g[LOOKAHEAD - 1] = val.g;
            self.b[LOOKAHEAD - 1] = val.b;
            self.blur[LOOKAHEAD - 1] = val_blur;
        }
    }
}

pub enum Denoised<T> {
    // Feed more frames
    NotYet,
    // No more
    Done,
    Frame {
        frame: ImgVec<RGBA8>,
        importance_map: ImgVec<u8>,
        meta: T,
    },
}

pub struct Denoiser<T> {
    /// the algo starts outputting on 3rd frame
    frames: usize,
    threshold: u32,
    splat: ImgVec<Acc>,
    processed: VecDeque<(ImgVec<RGBA8>, ImgVec<u8>)>,
    metadatas: VecDeque<T>,
}

#[derive(Debug)]
pub struct WrongSizeError;

impl<T> Denoiser<T> {
    #[inline]
    pub fn new(width: usize, height: usize, quality: u8) -> Result<Self, WrongSizeError> {
        let area = width.checked_mul(height).ok_or(WrongSizeError)?;
        let clear = Acc {
            r: Default::default(),
            g: Default::default(),
            b: Default::default(),
            blur: Default::default(),
            alpha_bits: (1 << LOOKAHEAD) - 1,
            bg_set: RGBA8::default(),
            stayed_for: 0,
            can_stay_for: 0,
        };
        Ok(Self {
            frames: 0,
            processed: VecDeque::with_capacity(LOOKAHEAD),
            metadatas: VecDeque::with_capacity(LOOKAHEAD),
            threshold: (55 - u32::from(quality) / 2).pow(2),
            splat: ImgVec::new(vec![clear; area], width, height),
        })
    }

    fn quick_append(&mut self, frame: ImgRef<RGBA8>, frame_blurred: ImgRef<RGB8>) {
        for ((acc, src), src_blur) in self.splat.pixels_mut().zip(frame.pixels()).zip(frame_blurred.pixels()) {
            acc.append(src, src_blur);
        }
    }

    /// Generate last few frames
    #[inline(never)]
    pub fn flush(&mut self) {
        while self.processed.len() < self.metadatas.len() {
            let mut median1 = Vec::with_capacity(self.splat.width() * self.splat.height());
            let mut imp_map1 = Vec::with_capacity(self.splat.width() * self.splat.height());

            for acc in self.splat.pixels_mut() {
                acc.append(RGBA8::new(0, 0, 0, 0), RGB8::new(0, 0, 0));
                let (m, i) = acc.next_pixel(self.threshold, self.frames & 1 != 0);
                median1.push_in_cap(m);
                imp_map1.push_in_cap(i);
            }

            // may need to push down first if there were not enough frames to fill the pipeline
            self.frames += 1;
            if self.frames >= LOOKAHEAD {
                let median1 = ImgVec::new(median1, self.splat.width(), self.splat.height());
                let imp_map1 = ImgVec::new(imp_map1, self.splat.width(), self.splat.height());
                self.processed.push_front((median1, imp_map1));
            }
        }
    }

    #[cfg(test)]
    fn push_frame_test(&mut self, frame: ImgRef<RGBA8>, frame_metadata: T) -> Result<(), WrongSizeError> {
        let frame_blurred = smart_blur(frame);
        self.push_frame(frame, frame_blurred.as_ref(), frame_metadata)
    }

    #[inline(never)]
    pub fn push_frame(&mut self, frame: ImgRef<RGBA8>, frame_blurred: ImgRef<RGB8>, frame_metadata: T) -> Result<(), WrongSizeError> {
        if frame.width() != self.splat.width() || frame.height() != self.splat.height() {
            return Err(WrongSizeError);
        }

        self.metadatas.push_front(frame_metadata);

        self.frames += 1;
        // Can't output anything yet
        if self.frames < LOOKAHEAD {
            self.quick_append(frame, frame_blurred);
            return Ok(());
        }

        let mut median = Vec::with_capacity(frame.width() * frame.height());
        let mut imp_map = Vec::with_capacity(frame.width() * frame.height());
        for ((acc, src), src_blur) in self.splat.pixels_mut().zip(frame.pixels()).zip(frame_blurred.pixels()) {
            acc.append(src, src_blur);

            let (m, i) = acc.next_pixel(self.threshold, self.frames & 1 != 0);
            median.push_in_cap(m);
            imp_map.push_in_cap(i);
        }

        let median = ImgVec::new(median, frame.width(), frame.height());
        let imp_map = ImgVec::new(imp_map, frame.width(), frame.height());
        self.processed.push_front((median, imp_map));
        Ok(())
    }

    #[inline]
    pub fn pop(&mut self) -> Denoised<T> {
        if let Some((frame, importance_map)) = self.processed.pop_back() {
            let meta = self.metadatas.pop_back().expect("meta");
            Denoised::Frame { frame, importance_map, meta }
        } else if !self.metadatas.is_empty() {
            Denoised::NotYet
        } else {
            Denoised::Done
        }
    }
}

impl Acc {
    fn next_pixel(&mut self, threshold: u32, odd_frame: bool) -> (RGBA8, u8) {
        // No previous bg set, so find a new one
        if let Some((curr, curr_blur)) = self.get(0) {
            let my_turn = cohort(curr) != odd_frame;
            let threshold = if my_turn { threshold } else { threshold * 2 };
            let diff_with_bg = if self.bg_set.a > 0 {
                let bg = color_diff(self.bg_set.rgb(), curr);
                let bg_blur = color_diff(self.bg_set.rgb(), curr_blur);
                if bg < bg_blur { bg } else { (bg + bg_blur) / 2 }
            } else { 1<<20 };

            if self.stayed_for < self.can_stay_for {
                self.stayed_for += 1;
                // If this is the second, corrective frame, then
                // give it weight proportional to its staying duration
                let max = if self.stayed_for > 1 { 0 } else {
                    [0, 40, 80, 100, 110][self.can_stay_for.min(4) as usize]
                };
                // min == 0 may wipe pixels totally clear, so give them at least a second chance,
                // if quality setting allows
                #[allow(overlapping_range_endpoints)]
                let min = match threshold {
                    0..=300 if self.stayed_for <= 3 => 1, // q >= 75
                    300..=500 if self.stayed_for <= 2 => 1,
                    400..=900 if self.stayed_for <= 1 => 1, // q >= 50
                    _ => 0,
                };
                return (self.bg_set, pixel_importance(diff_with_bg, threshold, min, max));
            }

            // if it's still good, keep rolling with it
            if diff_with_bg < threshold {
                return (self.bg_set, 0);
            }

            // See how long this bg can stay
            let mut stays_frames = 0;
            for i in 1..LOOKAHEAD {
                if self.get(i).map_or(false, |(c, blurred)| color_diff(c, curr) < threshold || color_diff(blurred, curr_blur) < threshold) {
                    stays_frames = i;
                } else {
                    break;
                }
            }

            // fast path for regular changing pixel
            if stays_frames == 0 {
                self.bg_set = curr.alpha(255);
                return (self.bg_set, pixel_importance(diff_with_bg, threshold, 10, 110));
            }
            let smoothed_curr = RGB8::new(
                get_median(&self.r, stays_frames + 1),
                get_median(&self.g, stays_frames + 1),
                get_median(&self.b, stays_frames + 1),
            );

            let imp = if stays_frames <= 1 {
                pixel_importance(diff_with_bg, threshold, 5, 80)
            } else if stays_frames == 2 {
                pixel_importance(diff_with_bg, threshold, 15, 190)
            } else {
                pixel_importance(diff_with_bg, threshold, 50, 205)
            };

            self.bg_set = smoothed_curr.alpha(255);
            // shorten stay-for to use overlapping ranges for smoother transitions
            self.can_stay_for = (stays_frames as u8).min(LOOKAHEAD as u8 - 1);
            self.stayed_for = 0;
            (self.bg_set, imp)
        } else {
            // pixels with importance == 0 are totally ignored, but that could skip frames
            // which need to set background to clear
            let imp = if self.bg_set.a > 0 {
                self.bg_set.a = 0;
                self.can_stay_for = 0;
                1
            } else { 0 };
            (RGBA8::new(0,0,0,0), imp)
        }
    }
}

/// Median of 9 neighboring pixels
macro_rules! median_channel {
    ($top:expr, $mid:expr, $bot:expr, $chan:ident) => {
        *[
            if $top.prev.a > 0 { $top.prev.$chan } else { $mid.curr.$chan },
            if $top.curr.a > 0 { $top.curr.$chan } else { $mid.curr.$chan },
            if $top.next.a > 0 { $top.next.$chan } else { $mid.curr.$chan },
            if $mid.prev.a > 0 { $mid.prev.$chan } else { $mid.curr.$chan },
            $mid.curr.$chan, // if the center pixel is transparent, the result won't be used
            if $mid.next.a > 0 { $mid.next.$chan } else { $mid.curr.$chan },
            if $bot.prev.a > 0 { $bot.prev.$chan } else { $mid.curr.$chan },
            if $bot.curr.a > 0 { $bot.curr.$chan } else { $mid.curr.$chan },
            if $bot.next.a > 0 { $bot.next.$chan } else { $mid.curr.$chan },
        ].select_nth_unstable(4).1
    }
}

/// Average of 9 neighboring pixels
macro_rules! blur_channel {
    ($top:expr, $mid:expr, $bot:expr, $chan:ident) => {{
        let mut tmp = 0u16;
        tmp += u16::from(if $top.prev.a > 0 { $top.prev.$chan } else { $mid.curr.$chan });
        tmp += u16::from(if $top.curr.a > 0 { $top.curr.$chan } else { $mid.curr.$chan });
        tmp += u16::from(if $top.next.a > 0 { $top.next.$chan } else { $mid.curr.$chan });
        tmp += u16::from(if $mid.prev.a > 0 { $mid.prev.$chan } else { $mid.curr.$chan });
        tmp += u16::from($mid.curr.$chan); // if the center pixel is transparent, the result won't be used
        tmp += u16::from(if $mid.next.a > 0 { $mid.next.$chan } else { $mid.curr.$chan });
        tmp += u16::from(if $bot.prev.a > 0 { $bot.prev.$chan } else { $mid.curr.$chan });
        tmp += u16::from(if $bot.curr.a > 0 { $bot.curr.$chan } else { $mid.curr.$chan });
        tmp += u16::from(if $bot.next.a > 0 { $bot.next.$chan } else { $mid.curr.$chan });
        (tmp / 9) as u8
    }}
}

#[inline(never)]
pub(crate) fn smart_blur(frame: ImgRef<RGBA8>) -> ImgVec<RGB8> {
    let mut out = Vec::with_capacity(frame.width() * frame.height());
    loop9_img(frame, |_,_, top, mid, bot| {
        out.push_in_cap(if mid.curr.a > 0 {
            let median_r = median_channel!(top, mid, bot, r);
            let median_g = median_channel!(top, mid, bot, g);
            let median_b = median_channel!(top, mid, bot, b);

            let blurred = RGB8::new(median_r, median_g, median_b);
            if color_diff(mid.curr.rgb(), blurred) < 16*16*6 {
                blurred
            } else {
                mid.curr.rgb()
            }
        } else { RGB8::new(255,0,255) });
    });
    ImgVec::new(out, frame.width(), frame.height())
}

#[inline(never)]
pub(crate) fn less_smart_blur(frame: ImgRef<RGBA8>) -> ImgVec<RGB8> {
    let mut out = Vec::with_capacity(frame.width() * frame.height());
    loop9_img(frame, |_,_, top, mid, bot| {
        out.push_in_cap(if mid.curr.a > 0 {
            let median_r = blur_channel!(top, mid, bot, r);
            let median_g = blur_channel!(top, mid, bot, g);
            let median_b = blur_channel!(top, mid, bot, b);

            let blurred = RGB8::new(median_r, median_g, median_b);
            if color_diff(mid.curr.rgb(), blurred) < 16*16*6 {
                blurred
            } else {
                mid.curr.rgb()
            }
        } else { RGB8::new(255,0,255) });
    });
    ImgVec::new(out, frame.width(), frame.height())
}

/// The idea is to split colors into two arbitrary groups, and flip-flop weight between them.
/// This might help quantization have less unique colors per frame, and catch up in the next frame.
#[inline(always)]
fn cohort(color: RGB8) -> bool {
    (color.r / 2 > color.g) != (color.b > 127)
}

/// importance = how much it exceeds percetible threshold
#[inline(always)]
fn pixel_importance(diff_with_bg: u32, threshold: u32, min: u8, max: u8) -> u8 {
    debug_assert!((u32::from(min) + u32::from(max)) <= 255);
    let exceeds = diff_with_bg.saturating_sub(threshold);
    min + (exceeds.saturating_mul(u32::from(max)) / (threshold.saturating_mul(48))).min(u32::from(max)) as u8
}

#[inline(always)]
fn avg8(a: u8, b: u8) -> u8 {
    ((u16::from(a) + u16::from(b)) / 2) as u8
}

#[inline(always)]
fn get_median(src: &[u8; LOOKAHEAD], len: usize) -> u8 {
    match len {
        1 => src[0],
        2 => avg8(src[0], src[1]),
        3 => {
            let mut tmp = [0u8; 3];
            tmp.copy_from_slice(&src[0..3]);
            tmp.sort_unstable();
            tmp[1]
        },
        4 => {
            let mut tmp = [0u8; 4];
            tmp.copy_from_slice(&src[0..4]);
            tmp.sort_unstable();
            avg8(tmp[1], tmp[2])
        },
        5 => {
            let mut tmp = [0u8; 5];
            tmp.copy_from_slice(&src[0..5]);
            tmp.sort_unstable();
            tmp[2]
        },
        _ => unreachable!(),
    }
}

#[inline]
fn color_diff(x: RGB8, y: RGB8) -> u32 {
    let x = x.map(i32::from);
    let y = y.map(i32::from);

    (x.r - y.r).pow(2) as u32 * 2 +
    (x.g - y.g).pow(2) as u32 * 3 +
    (x.b - y.b).pow(2) as u32
}

#[track_caller]
#[cfg(test)]
fn px<T>(f: Denoised<T>) -> (RGBA8, T) {
    if let Denoised::Frame { frame, meta, .. } = f {
        (frame.pixels().next().unwrap(), meta)
    } else { panic!("no frame") }
}

#[test]
fn one() {
    let mut d = Denoiser::new(1,1, 100).unwrap();
    let w = RGBA8::new(255,255,255,255);
    let frame = ImgVec::new(vec![w], 1, 1);
    let frame_blurred = smart_blur(frame.as_ref());

    d.push_frame(frame.as_ref(), frame_blurred.as_ref(), 0).unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.flush();
    assert_eq!(px(d.pop()), (w, 0));
    assert!(matches!(d.pop(), Denoised::Done));
}

#[test]
fn two() {
    let mut d = Denoiser::new(1,1, 100).unwrap();
    let w = RGBA8::new(254,253,252,255);
    let b = RGBA8::new(8,7,0,255);
    d.push_frame_test(ImgVec::new(vec![w], 1, 1).as_ref(), 0).unwrap();
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), 1).unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.flush();
    assert_eq!(px(d.pop()), (w, 0));
    assert_eq!(px(d.pop()), (b, 1));
    assert!(matches!(d.pop(), Denoised::Done));
}

#[test]
fn three() {
    let mut d = Denoiser::new(1,1, 100).unwrap();
    let w = RGBA8::new(254,253,252,255);
    let b = RGBA8::new(8,7,0,255);
    d.push_frame_test(ImgVec::new(vec![w], 1, 1).as_ref(), 0).unwrap();
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), 1).unwrap();
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), 2).unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.flush();
    assert_eq!(px(d.pop()), (w, 0));
    assert_eq!(px(d.pop()), (b, 1));
    assert_eq!(px(d.pop()), (b, 2));
    assert!(matches!(d.pop(), Denoised::Done));
}


#[test]
fn four() {
    let mut d = Denoiser::new(1,1, 100).unwrap();
    let w = RGBA8::new(254,253,252,255);
    let b = RGBA8::new(8,7,0,255);
    let t = RGBA8::new(0,0,0,0);
    d.push_frame_test(ImgVec::new(vec![w], 1, 1).as_ref(), 0).unwrap();
    d.push_frame_test(ImgVec::new(vec![t], 1, 1).as_ref(), 1).unwrap();
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), 2).unwrap();
    d.push_frame_test(ImgVec::new(vec![w], 1, 1).as_ref(), 3).unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.flush();
    assert_eq!(px(d.pop()), (w, 0));
    assert_eq!(px(d.pop()), (t, 1));
    assert_eq!(px(d.pop()), (b, 2));
    assert_eq!(px(d.pop()), (w, 3));
    assert!(matches!(d.pop(), Denoised::Done));
}

#[test]
fn five() {
    let mut d = Denoiser::new(1,1, 100).unwrap();
    let w = RGBA8::new(254,253,252,255);
    let b = RGBA8::new(8,7,0,255);
    let t = RGBA8::new(0,0,0,0);
    d.push_frame_test(ImgVec::new(vec![w], 1, 1).as_ref(), 0).unwrap();
    d.push_frame_test(ImgVec::new(vec![t], 1, 1).as_ref(), 1).unwrap();
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), 2).unwrap();
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), 3).unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.push_frame_test(ImgVec::new(vec![w], 1, 1).as_ref(), 4).unwrap();
    assert_eq!(px(d.pop()), (w, 0));
    d.flush();
    assert_eq!(px(d.pop()), (t, 1));
    assert_eq!(px(d.pop()), (b, 2));
    assert_eq!(px(d.pop()), (b, 3));
    assert_eq!(px(d.pop()), (w, 4));
    assert!(matches!(d.pop(), Denoised::Done));
}

#[test]
fn six() {
    let mut d = Denoiser::new(1,1, 100).unwrap();
    let w = RGBA8::new(254,253,252,255);
    let b = RGBA8::new(8,7,0,255);
    let t = RGBA8::new(0,0,0,0);
    let x = RGBA8::new(4,5,6,255);
    d.push_frame_test(ImgVec::new(vec![w], 1, 1).as_ref(), 0).unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), 1).unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), 2).unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.push_frame_test(ImgVec::new(vec![t], 1, 1).as_ref(), 3).unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.push_frame_test(ImgVec::new(vec![w], 1, 1).as_ref(), 4).unwrap();
    assert_eq!(px(d.pop()), (w, 0));
    d.push_frame_test(ImgVec::new(vec![x], 1, 1).as_ref(), 5).unwrap();
    d.flush();
    assert_eq!(px(d.pop()), (b, 1));
    assert_eq!(px(d.pop()), (b, 2));
    assert_eq!(px(d.pop()), (t, 3));
    assert_eq!(px(d.pop()), (w, 4));
    assert_eq!(px(d.pop()), (x, 5));
    assert!(matches!(d.pop(), Denoised::Done));
}


#[test]
fn many() {
    let mut d = Denoiser::new(1,1, 100).unwrap();
    let w = RGBA8::new(255,254,253,255);
    let b = RGBA8::new(1,2,3,255);
    let t = RGBA8::new(0,0,0,0);
    d.push_frame_test(ImgVec::new(vec![w], 1, 1).as_ref(), "w0").unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.push_frame_test(ImgVec::new(vec![w], 1, 1).as_ref(), "w1").unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), "b2").unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), "b3").unwrap();
    assert!(matches!(d.pop(), Denoised::NotYet));
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), "b4").unwrap();
    assert_eq!(px(d.pop()), (w, "w0"));
    d.push_frame_test(ImgVec::new(vec![t], 1, 1).as_ref(), "t5").unwrap();
    assert_eq!(px(d.pop()), (w, "w1"));
    d.push_frame_test(ImgVec::new(vec![b], 1, 1).as_ref(), "b6").unwrap();
    assert_eq!(px(d.pop()), (b, "b2"));
    d.flush();
    assert_eq!(px(d.pop()), (b, "b3"));
    assert_eq!(px(d.pop()), (b, "b4"));
    assert_eq!(px(d.pop()), (t, "t5"));
    assert_eq!(px(d.pop()), (b, "b6"));
    assert!(matches!(d.pop(), Denoised::Done));
}
