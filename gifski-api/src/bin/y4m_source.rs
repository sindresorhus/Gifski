//! This is for reading GIFs as an input for re-encoding as another GIF

use std::io::BufReader;
use std::io::Read;
use imgref::ImgVec;
use y4m::Colorspace;
use y4m::Decoder;
use gifski::Collector;
use yuv::color::MatrixCoefficients;
use yuv::color::Range;
use yuv::convert::RGBConvert;
use yuv::YUV;
use crate::{SrcPath, BinResult};
use crate::source::{Fps, Source};

pub struct Y4MDecoder {
    fps: Fps,
    decoder: Decoder<Box<dyn Read>>,
    file_size: Option<u64>,
}

impl Y4MDecoder {
    pub fn new(src: SrcPath, fps: Fps) -> BinResult<Self> {
        let mut file_size = None;
        let reader = match src {
            SrcPath::Path(path) => {
                let f = std::fs::File::open(path)?;
                let m = f.metadata()?;
                #[cfg(unix)] {
                    use std::os::unix::fs::MetadataExt;
                    file_size = Some(m.size());
                }
                #[cfg(windows)] {
                    use std::os::windows::fs::MetadataExt;
                    file_size = Some(m.file_size());
                }
                Box::new(BufReader::new(f)) as Box<dyn Read>
            },
            SrcPath::Stdin(buf) => Box::new(buf) as _,
        };

        Ok(Self {
            file_size,
            fps,
            decoder: Decoder::new(reader)?,
        })
    }
}

enum Samp {
    Mono,
    S1x1,
    S2x1,
    S2x2,
}

impl Source for Y4MDecoder {
    fn total_frames(&self) -> Option<u64> {
        self.file_size.map(|file_size| {
            let w = self.decoder.get_width();
            let h = self.decoder.get_height();
            let d = self.decoder.get_bytes_per_sample();
            let s = match self.decoder.get_colorspace() {
                Colorspace::Cmono => 4,
                Colorspace::Cmono12 => 4,
                Colorspace::C420 => 6,
                Colorspace::C420p10 => 6,
                Colorspace::C420p12 => 6,
                Colorspace::C420jpeg => 6,
                Colorspace::C420paldv => 6,
                Colorspace::C420mpeg2 => 6,
                Colorspace::C422 => 8,
                Colorspace::C422p10 => 8,
                Colorspace::C422p12 => 8,
                Colorspace::C444 => 12,
                Colorspace::C444p10 => 12,
                Colorspace::C444p12 => 12,
                _ => 12,
            };
            file_size.saturating_sub(self.decoder.get_raw_params().len() as _) / (w * h * d * s / 4 + 6) as u64
        })
    }
    fn collect(&mut self, c: &mut Collector) -> BinResult<()> {
        let fps = self.decoder.get_framerate();
        let frame_time = 1. / (fps.num as f64 / fps.den as f64);
        let wanted_frame_time = 1. / f64::from(self.fps.fps);
        let width = self.decoder.get_width();
        let height = self.decoder.get_height();
        let raw_params_str = &*String::from_utf8_lossy(self.decoder.get_raw_params()).into_owned();
        let range = raw_params_str.split_once("COLORRANGE=").map(|(_, r)| {
            if r.starts_with("LIMIT") { Range::Limited } else { Range::Full }
        });

        let sd_or_hd = if height <= 480 && width <= 720 { MatrixCoefficients::BT601 } else { MatrixCoefficients::BT709 };

        let (samp, conv) = match self.decoder.get_colorspace() {
            Colorspace::Cmono => (Samp::Mono, RGBConvert::<u8>::new(range.unwrap_or(Range::Full), MatrixCoefficients::Identity)),
            Colorspace::Cmono12 => return Err("Y4M with Cmono12 is not supported yet".into()),
            Colorspace::C420 => (Samp::S2x2, RGBConvert::<u8>::new(range.unwrap_or(Range::Limited), MatrixCoefficients::BT601)),
            Colorspace::C420p10 => return Err("Y4M with C420p10 is not supported yet".into()),
            Colorspace::C420p12 => return Err("Y4M with C420p12 is not supported yet".into()),
            Colorspace::C420jpeg => (Samp::S2x2, RGBConvert::<u8>::new(range.unwrap_or(Range::Full), MatrixCoefficients::BT601)),
            Colorspace::C420paldv => (Samp::S2x2, RGBConvert::<u8>::new(range.unwrap_or(Range::Limited), MatrixCoefficients::BT601)),
            Colorspace::C420mpeg2 => (Samp::S2x2, RGBConvert::<u8>::new(range.unwrap_or(Range::Limited), sd_or_hd)),
            Colorspace::C422 => (Samp::S2x1, RGBConvert::<u8>::new(range.unwrap_or(Range::Limited), sd_or_hd)),
            Colorspace::C422p10 => return Err("Y4M with C422p10 is not supported yet".into()),
            Colorspace::C422p12 => return Err("Y4M with C422p12 is not supported yet".into()),
            Colorspace::C444 => (Samp::S1x1, RGBConvert::<u8>::new(range.unwrap_or(Range::Full), MatrixCoefficients::BT709)),
            Colorspace::C444p10 => return Err("Y4M with C444p10 is not supported yet".into()),
            Colorspace::C444p12 => return Err("Y4M with C444p12 is not supported yet".into()),
            _ => return Err(format!("Y4M uses unsupported color mode {raw_params_str}").into()),
        };
        let conv = conv?;
        if width == 0 || width > u16::MAX as _ || height == 0 || height > u16::MAX as _ {
            return Err("Video too large".into());
        }

        #[cold]
        fn bad_frame(mode: &str) -> BinResult<()> {
            Err(format!("Bad Y4M frame (using {mode})").into())
        }

        let mut idx = 0;
        let mut presentation_timestamp = 0.0;
        let mut wanted_pts = 0.0;
        loop {
            match self.decoder.read_frame() {
                Ok(frame) => {
                    let this_frame_pts = presentation_timestamp / f64::from(self.fps.speed);
                    presentation_timestamp += frame_time;
                    if presentation_timestamp < wanted_pts {
                        continue; // skip a frame
                    }
                    wanted_pts += wanted_frame_time;

                    let y = frame.get_y_plane();
                    if y.is_empty() {
                        return bad_frame(raw_params_str);
                    }
                    let u = frame.get_u_plane();
                    let v = frame.get_v_plane();
                    if v.len() != u.len() {
                        return bad_frame(raw_params_str);
                    }

                    let mut out = Vec::new();
                    out.try_reserve(width * height)?;
                    match samp {
                        Samp::Mono => todo!(),
                        Samp::S1x1 => {
                            if v.len() != y.len() {
                                return bad_frame(raw_params_str);
                            }

                            let y = y.chunks_exact(width);
                            let u = u.chunks_exact(width);
                            let v = v.chunks_exact(width);
                            if y.len() != v.len() {
                                return bad_frame(raw_params_str);
                            }
                            for (y, (u, v)) in y.zip(u.zip(v)) {
                                out.extend(
                                    y.iter().copied().zip(u.iter().copied().zip(v.iter().copied()))
                                    .map(|(y, (u, v))| {
                                        conv.to_rgb(YUV {y, u, v}).with_alpha(255)
                                    }));
                            }
                        },
                        Samp::S2x1 => {
                            let y = y.chunks_exact(width);
                            let u = u.chunks_exact((width+1)/2);
                            let v = v.chunks_exact((width+1)/2);
                            if y.len() != v.len() {
                                return bad_frame(raw_params_str);
                            }
                            for (y, (u, v)) in y.zip(u.zip(v)) {
                                let u = u.iter().copied().flat_map(|x| [x, x]);
                                let v = v.iter().copied().flat_map(|x| [x, x]);
                                out.extend(
                                    y.iter().copied().zip(u.zip(v))
                                    .map(|(y, (u, v))| {
                                        conv.to_rgb(YUV {y, u, v}).with_alpha(255)
                                    }));
                            }
                        },
                        Samp::S2x2 => {
                            let y = y.chunks_exact(width);
                            let u = u.chunks_exact((width+1)/2).flat_map(|r| [r, r]);
                            let v = v.chunks_exact((width+1)/2).flat_map(|r| [r, r]);
                            for (y, (u, v)) in y.zip(u.zip(v)) {
                                let u = u.iter().copied().flat_map(|x| [x, x]);
                                let v = v.iter().copied().flat_map(|x| [x, x]);
                                out.extend(
                                    y.iter().copied().zip(u.zip(v))
                                    .map(|(y, (u, v))| {
                                        conv.to_rgb(YUV {y, u, v}).with_alpha(255)
                                    }));
                            }
                        },
                    };
                    if out.len() != width * height {
                        return bad_frame(raw_params_str);
                    }
                    let pixels = ImgVec::new(out, width, height);

                    c.add_frame_rgba(idx, pixels, this_frame_pts)?;
                    idx += 1;
                },
                Err(y4m::Error::EOF) => break,
                Err(e) => return Err(e.into()),
            }
        }
        Ok(())
    }
}
