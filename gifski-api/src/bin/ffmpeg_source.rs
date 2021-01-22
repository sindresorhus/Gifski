use crate::BinResult;
use gifski::Collector;
use gifski::Settings;
use imgref::*;
use rgb::*;
use crate::source::*;
use std::path::Path;

pub struct FfmpegDecoder {
    input_context: ffmpeg::format::context::Input,
    frames: u64,
    rate: Fps,
    settings: Settings,
}

impl Source for FfmpegDecoder {
    fn total_frames(&self) -> u64 {
        self.frames
    }
    fn collect(&mut self, dest: Collector) -> BinResult<()> {
        self.collect_frames(dest)
    }
}

impl FfmpegDecoder {
    pub fn new(path: &Path, rate: Fps, settings: Settings) -> BinResult<Self> {
        ffmpeg::init().map_err(|e| format!("Unable to initialize ffmpeg: {}", e))?;
        let input_context = ffmpeg::format::input(&path)
            .map_err(|e| format!("Unable to open video file {}: {}", path.display(), e))?;
        // take fps override into account
        let filter_fps = rate.fps / rate.speed;
        let stream = input_context.streams().best(ffmpeg::media::Type::Video).ok_or("The file has no video tracks")?;
        let time_base = stream.time_base().numerator() as f64 / stream.time_base().denominator() as f64;
        let frames = (stream.duration() as f64 * time_base * filter_fps as f64).ceil() as u64;
        Ok(Self {
            input_context,
            frames,
            rate,
            settings,
        })
    }

    pub fn collect_frames(&mut self, mut dest: Collector) -> BinResult<()> {
        let (stream_index, mut decoder, mut filter) = {
            let filter_fps = self.rate.fps / self.rate.speed;
            let stream = self.input_context.streams().best(ffmpeg::media::Type::Video).ok_or("The file has no video tracks")?;

            let decoder = stream.codec().decoder().video().map_err(|e| format!("Unable to decode the codec used in the video: {}", e))?;

            let (dest_width, dest_height) = self.settings.dimensions_for_image(decoder.width() as _, decoder.height() as _);

            let buffer_args = format!("width={}:height={}:video_size={}x{}:pix_fmt={}:time_base={}:sar={}",
                dest_width,
                dest_height,
                decoder.width(),
                decoder.height(),
                decoder.format().descriptor().ok_or("ffmpeg format error")?.name(),
                stream.time_base(),
                (|sar: ffmpeg::util::rational::Rational| match sar.numerator() {
                    0 => "1".to_string(),
                    _ => format!("{}/{}", sar.numerator(), sar.denominator()),
                })(decoder.aspect_ratio()),
            );
            let mut filter = ffmpeg::filter::Graph::new();
            filter.add(&ffmpeg::filter::find("buffer").ok_or("ffmpeg format error")?, "in", &buffer_args)?;
            filter.add(&ffmpeg::filter::find("buffersink").ok_or("ffmpeg format error")?, "out", "")?;
            filter.output("in", 0)?.input("out", 0)?.parse(&format!("fps=fps={},format=rgba", filter_fps))?;
            filter.validate()?;
            (stream.index(), decoder, filter)
        };


        let mut add_frame = |rgba_frame: &ffmpeg::util::frame::Video, pts: f64, pos: i64| -> BinResult<()> {
            let stride = rgba_frame.stride(0) as usize;
            if stride % 4 != 0 {
                Err("incompatible video")?;
            }
            let rgba_frame = ImgVec::new_stride(
                rgba_frame.data(0).as_rgba().to_owned(),
                rgba_frame.width() as usize,
                rgba_frame.height() as usize,
                stride / 4,
            );
            Ok(dest.add_frame_rgba(pos as usize, rgba_frame, pts)?)
        };

        let mut packets = self.input_context.packets();
        let mut vid_frame = ffmpeg::util::frame::Video::empty();
        let mut filt_frame = ffmpeg::util::frame::Video::empty();
        let mut i = 0;
        let mut pts_last_packet = 0;
        let mut delayed_frames = 0;
        let pts_frame_step = 1.0 / self.rate.fps as f64;

        loop {
            let (packet, packet_is_empty) = if let Some((s, packet)) = packets.next() {
                if s.index() != stream_index {
                    continue;
                }
                pts_last_packet = packet.pts().ok_or("ffmpeg format error")? + packet.duration();
                (packet, false)
            } else {
                (ffmpeg::Packet::empty(), true)
            };
            let decoded = decoder.decode(&packet, &mut vid_frame)?;
            if !decoded || 0 == vid_frame.width() {
                if packet_is_empty {
                    if delayed_frames == 0 {
                        break;
                    }
                } else {
                    delayed_frames += 1;
                }
                continue;
            }
            if packet_is_empty {
                delayed_frames -= 1;
            }

            filter.get("in").ok_or("ffmpeg format error")?.source().add(&vid_frame)?;
            let mut out = filter.get("out").ok_or("ffmpeg format error")?;
            let mut out = out.sink();
            while let Ok(..) = out.frame(&mut filt_frame) {
                add_frame(&filt_frame, pts_frame_step * i as f64, i)?;
                i += 1;
            }
        }

        filter.get("in").ok_or("ffmpeg format error")?.source().close(pts_last_packet)?;
        let mut out = filter.get("out").ok_or("ffmpeg format error")?;
        let mut out = out.sink();
        while let Ok(..) = out.frame(&mut filt_frame) {
            add_frame(&filt_frame, pts_frame_step * i as f64, i)?;
            i += 1;
        }
        Ok(())
    }
}
