pub use imgref::ImgRef;
use imgref::ImgVec;
use rgb::ComponentMap;
use rgb::RGB8;
pub use rgb::RGBA8;

const LOOKAHEAD: usize = 5;

#[derive(Debug, Default, Copy, Clone)]
struct Acc {
    r: [u8; LOOKAHEAD],
    g: [u8; LOOKAHEAD],
    b: [u8; LOOKAHEAD],
    alpha_bits: u8,
    can_stay_for: u8,
    stayed_for: u8,
    bg_set: RGBA8,
}

impl Acc {
    #[inline(always)]
    pub fn get(&self, idx: usize) -> Option<RGB8> {
        if self.alpha_bits & (1 << idx) == 0 {
            Some(RGB8::new(self.r[idx], self.g[idx], self.b[idx]))
        } else {
            None
        }
    }

    #[inline(always)]
    pub fn append(&mut self, val: RGBA8) {
        for n in 1..LOOKAHEAD {
            self.r[n - 1] = self.r[n];
            self.g[n - 1] = self.g[n];
            self.b[n - 1] = self.b[n];
        }
        self.alpha_bits >>= 1;

        if val.a < 128 {
            self.alpha_bits |= 1 << (LOOKAHEAD - 1);
        } else {
            self.r[LOOKAHEAD - 1] = val.r;
            self.g[LOOKAHEAD - 1] = val.g;
            self.b[LOOKAHEAD - 1] = val.b;
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
    processed: Vec<(ImgVec<RGBA8>, ImgVec<u8>)>,
    metadatas: Vec<T>,
}

impl<T> Denoiser<T> {
    #[inline]
    pub fn new(width: usize, height: usize, quality: u8) -> Self {
        let area = width.checked_mul(height).unwrap();
        let clear = Acc {
            r: Default::default(),
            g: Default::default(),
            b: Default::default(),
            alpha_bits: !0,
            bg_set: Default::default(),
            stayed_for: 0,
            can_stay_for: 0,
        };
        Self {
            frames: 0,
            processed: Vec::with_capacity(4),
            metadatas: Vec::with_capacity(4),
            threshold: (55 - u32::from(quality) / 2).pow(2),
            splat: ImgVec::new(vec![clear; area], width, height),
        }
    }

    fn quick_append(&mut self, frame: ImgRef<RGBA8>) {
        for (acc, src) in self.splat.pixels_mut().zip(frame.pixels()) {
            acc.append(src);
        }
    }

    /// Generate last few frames
    pub fn flush(&mut self) {
        while self.processed.len() < self.metadatas.len() {
            let mut median1 = Vec::with_capacity(self.splat.width() * self.splat.height());
            let mut imp_map1 = Vec::with_capacity(self.splat.width() * self.splat.height());

            for acc in self.splat.pixels_mut() {
                acc.append(RGBA8::new(0, 0, 0, 0));
                let (m, i) = Self::acc(acc, self.threshold, self.frames & 1 != 0);
                median1.push(m);
                imp_map1.push(i);
            }

            // may need to push down first if there were not enough frames to fill the pipeline
            if self.frames < LOOKAHEAD {
                self.frames += 1;
            } else {
                let median1 = ImgVec::new(median1, self.splat.width(), self.splat.height());
                let imp_map1 = ImgVec::new(imp_map1, self.splat.width(), self.splat.height());
                self.processed.insert(0, (median1, imp_map1));
            }
        }
        // Kill NotYet case later
        if self.frames <= LOOKAHEAD {
            self.frames = LOOKAHEAD + 1;
        }
    }

    pub fn push_frame(&mut self, frame: ImgRef<RGBA8>, frame_metadata: T) {
        assert_eq!(frame.width(), self.splat.width());
        assert_eq!(frame.height(), self.splat.height());

        self.metadatas.insert(0, frame_metadata);

        // Can't output anything yet
        if self.frames < LOOKAHEAD {
            self.frames += 1;
            self.quick_append(frame);
            return;
        }
        self.frames += 1;

        let mut median = Vec::with_capacity(frame.width() * frame.height());
        let mut imp_map = Vec::with_capacity(frame.width() * frame.height());
        for (acc, src) in self.splat.pixels_mut().zip(frame.pixels()) {
            acc.append(src);

            let (m, i) = Self::acc(acc, self.threshold, self.frames & 1 != 0);
            median.push(m);
            imp_map.push(i);
        }

        let median = ImgVec::new(median, frame.width(), frame.height());
        let imp_map = ImgVec::new(imp_map, frame.width(), frame.height());
        self.processed.insert(0, (median, imp_map));
    }

    pub fn pop(&mut self) -> Denoised<T> {
        if let Some((frame, importance_map)) = self.processed.pop() {
            let meta = self.metadatas.pop().expect("meta");
            Denoised::Frame { frame, importance_map, meta }
        } else if self.frames <= LOOKAHEAD {
            Denoised::NotYet
        } else {
            Denoised::Done
        }
    }

    fn acc(acc: &mut Acc, threshold: u32, odd_frame: bool) -> (RGBA8, u8) {
        // No previous bg set, so find a new one
        if let Some(curr) = acc.get(0) {
            let my_turn = cohort(curr) != odd_frame;
            let threshold = if my_turn { threshold } else { threshold * 2 };
            let diff_with_bg = if acc.bg_set.a > 0 { color_diff(acc.bg_set.rgb(), curr) } else { 1<<20 };

            if acc.stayed_for < acc.can_stay_for {
                acc.stayed_for += 1;
                // If this is the second, corrective frame, then
                // give it weight proportional to its staying duration
                let max = if acc.stayed_for != 1 { 0 } else {
                    [0, 40, 80, 100, 110][acc.can_stay_for.min(4) as usize]
                };
                return (acc.bg_set, imp(diff_with_bg, threshold, 0, max));
            }

            // if it's still good, keep rolling with it
            if diff_with_bg < threshold {
                return (acc.bg_set, 0);
            }

            // See how long this bg can stay
            let mut stays_frames = 0;
            for i in 1..LOOKAHEAD {
                if acc.get(i).map_or(false, |c| color_diff(c, curr) < threshold) {
                    stays_frames = i;
                } else {
                    break;
                }
            }

            // fast path for regular changing pixel
            if stays_frames == 0 {
                acc.bg_set = curr.alpha(255);
                return (acc.bg_set, imp(diff_with_bg, threshold, 10, 110));
            }
            let smoothed_curr = RGB8::new(
                get_median(&acc.r, stays_frames + 1),
                get_median(&acc.g, stays_frames + 1),
                get_median(&acc.b, stays_frames + 1),
            );

            let imp = if stays_frames <= 1 {
                imp(diff_with_bg, threshold, 5, 80)
            } else if stays_frames == 2 {
                imp(diff_with_bg, threshold, 15, 190)
            } else {
                imp(diff_with_bg, threshold, 50, 205)
            };

            acc.bg_set = smoothed_curr.alpha(255);
            // shorten stay-for to use overlapping ranges for smoother transitions
            acc.can_stay_for = (stays_frames as u8).min(LOOKAHEAD as u8 - 1);
            acc.stayed_for = 0;
            (acc.bg_set, imp)
        } else {
            // pixels with importance == 0 are totally ignored, but that could skip frames
            // which need to set background to clear
            let imp = if acc.bg_set.a > 0 {
                acc.bg_set.a = 0;
                acc.can_stay_for = 0;
                1
            } else { 0 };
            (RGBA8::new(0,0,0,0), imp)
        }
    }
}

/// The idea is to split colors into two arbitrary groups, and flip-flop weight between them.
/// This might help quantization have less unique colors per frame, and catch up in the next frame.
#[inline(always)]
fn cohort(color: RGB8) -> bool {
    (color.r / 2 > color.g) != (color.b > 127)
}

/// importance = how much it exceeds percetible threshold
#[inline(always)]
fn imp(diff_with_bg: u32, threshold: u32, min: u8, max: u8) -> u8 {
    assert!((min as u32 + max as u32) <= 255);
    let exceeds = diff_with_bg.saturating_sub(threshold);
    min + (exceeds.saturating_mul(max as u32) / (threshold.saturating_mul(48))).min(max as u32) as u8
}

#[inline(always)]
fn avg8(a: u8, b: u8) -> u8 {
    ((a as u16 + b as u16) / 2) as u8
}

#[inline(always)]
fn get_median(src: &[u8; LOOKAHEAD], len: usize) -> u8 {
    match len {
        1 => src[0],
        2 => avg8(src[0], src[1]),
        3 => {
            let mut tmp = [0u8; 3];
            tmp.copy_from_slice(&src[0 .. len]);
            tmp.sort_unstable();
            tmp[1]
        },
        4 => {
            let mut tmp = [0u8; 4];
            tmp.copy_from_slice(&src[0 .. len]);
            tmp.sort_unstable();
            avg8(tmp[1], tmp[2])
        },
        5 => {
            let mut tmp = [0u8; 5];
            tmp.copy_from_slice(&src[0 .. len]);
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
