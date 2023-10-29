#![allow(clippy::bool_to_int_with_if)]
#![allow(clippy::cast_possible_truncation)]
#![allow(clippy::enum_glob_use)]
#![allow(clippy::match_same_arms)]
#![allow(clippy::missing_errors_doc)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::needless_pass_by_value)]
#![allow(clippy::redundant_closure_for_method_calls)]
#![allow(clippy::wildcard_imports)]

use clap::builder::NonEmptyStringValueParser;
use std::io::Read;
use std::io::Stdout;
use gifski::{Settings, Repeat};
use clap::value_parser;

#[cfg(feature = "video")]
mod ffmpeg_source;
mod png;
mod gif;
mod source;
use crate::source::Source;

use gifski::progress::{NoProgress, ProgressReporter};

pub type BinResult<T, E = Box<dyn std::error::Error + Send + Sync>> = Result<T, E>;

use clap::{Command, Arg, ArgAction};

use std::env;
use std::fmt;
use std::fs::File;
use std::io;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

#[cfg(feature = "video")]
const VIDEO_FRAMES_ARG_HELP: &str = "one video file supported by FFmpeg, or multiple PNG image files";
#[cfg(not(feature = "video"))]
const VIDEO_FRAMES_ARG_HELP: &str = "PNG image files for the animation frames";

fn main() {
    if let Err(e) = bin_main() {
        eprintln!("error: {e}");
        if let Some(e) = e.source() {
            eprintln!("error: {e}");
        }
        std::process::exit(1);
    }
}

#[allow(clippy::float_cmp)]
fn bin_main() -> BinResult<()> {
    let matches = Command::new(clap::crate_name!())
                        .version(clap::crate_version!())
                        .about("https://gif.ski by Kornel Lesiński")
                        .arg_required_else_help(true)
                        .allow_negative_numbers(true)
                        .arg(Arg::new("output")
                            .long("output")
                            .short('o')
                            .help("Destination file to write to; \"-\" means stdout")
                            .num_args(1)
                            .value_name("a.gif")
                            .value_parser(value_parser!(PathBuf))
                            .required(true))
                        .arg(Arg::new("fps")
                            .long("fps")
                            .short('r')
                            .help("Frame rate of animation. If using PNG files as \
                                   input, this means the speed, as all frames are \
                                   kept. If video is used, it will be resampled to \
                                   this constant rate by dropping and/or duplicating \
                                   frames")
                            .value_parser(value_parser!(f32))
                            .value_name("num")
                            .default_value("20"))
                        .arg(Arg::new("fast-forward")
                            .long("fast-forward")
                            .help("Multiply speed of video by a factor\n(no effect when using images as input)")
                            .value_parser(value_parser!(f32))
                            .value_name("x")
                            .default_value("1"))
                        .arg(Arg::new("fast")
                            .num_args(0)
                            .action(ArgAction::SetTrue)
                            .long("fast")
                            .help("50% faster encoding, but 10% worse quality and larger file size"))
                        .arg(Arg::new("extra")
                            .long("extra")
                            .conflicts_with("fast")
                            .num_args(0)
                            .action(ArgAction::SetTrue)
                            .help("50% slower encoding, but 1% better quality"))
                        .arg(Arg::new("quality")
                            .long("quality")
                            .short('Q')
                            .value_name("1-100")
                            .value_parser(value_parser!(u8).range(1..=100))
                            .num_args(1)
                            .default_value("90")
                            .help("Lower quality may give smaller file"))
                        .arg(Arg::new("motion-quality")
                            .long("motion-quality")
                            .value_name("1-100")
                            .value_parser(value_parser!(u8).range(1..=100))
                            .num_args(1)
                            .help("Lower values reduce motion"))
                        .arg(Arg::new("lossy-quality")
                            .long("lossy-quality")
                            .value_name("1-100")
                            .value_parser(value_parser!(u8).range(1..=100))
                            .num_args(1)
                            .help("Lower values introduce noise and streaks"))
                        .arg(Arg::new("width")
                            .long("width")
                            .short('W')
                            .num_args(1)
                            .value_parser(value_parser!(u32))
                            .value_name("px")
                            .help("Maximum width.\nBy default anims are limited to about 800x600"))
                        .arg(Arg::new("height")
                            .long("height")
                            .short('H')
                            .num_args(1)
                            .value_parser(value_parser!(u32))
                            .value_name("px")
                            .help("Maximum height (stretches if the width is also set)"))
                        .arg(Arg::new("nosort")
                            .alias("nosort")
                            .long("no-sort")
                            .num_args(0)
                            .action(ArgAction::SetTrue)
                            .hide_short_help(true)
                            .help("Use files exactly in the order given, rather than sorted"))
                        .arg(Arg::new("quiet")
                            .long("quiet")
                            .short('q')
                            .num_args(0)
                            .action(ArgAction::SetTrue)
                            .help("Do not display anything on standard output/console"))
                        .arg(Arg::new("FILES")
                            .help(VIDEO_FRAMES_ARG_HELP)
                            .num_args(1..)
                            .value_parser(NonEmptyStringValueParser::new())
                            .use_value_delimiter(false)
                            .required(true))
                        .arg(Arg::new("repeat")
                            .long("repeat")
                            .help("Number of times the animation is repeated (-1 none, 0 forever or <value> repetitions")
                            .num_args(1)
                            .value_parser(value_parser!(i16))
                            .value_name("num"))
                        .arg(Arg::new("fixed-color")
                            .long("fixed-color")
                            .help("Always include this color in the palette")
                            .hide_short_help(true)
                            .num_args(1)
                            .action(ArgAction::Append)
                            .value_parser(parse_colors)
                            .value_name("RGBHEX"))
                        .arg(Arg::new("matte")
                            .long("matte")
                            .help("Background color for semitransparent pixels")
                            .num_args(1)
                            .value_parser(parse_color)
                            .value_name("RGBHEX"))
                        .get_matches_from(wild::args_os());

    let mut frames: Vec<&str> = matches.get_many::<String>("FILES").ok_or("?")?.map(|s| s.as_str()).collect();
    if !matches.get_flag("nosort") {
        frames.sort_by(|a, b| natord::compare(a, b));
    }
    let frames: Vec<_> = frames.into_iter().map(PathBuf::from).collect();

    let output_path = DestPath::new(matches.get_one::<PathBuf>("output").ok_or("?")?);
    let width = matches.get_one::<u32>("width").copied();
    let height = matches.get_one::<u32>("height").copied();
    let repeat_int = matches.get_one::<i16>("repeat").copied().unwrap_or(0);
    let repeat = match repeat_int {
        -1 => Repeat::Finite(0),
        0 => Repeat::Infinite,
        _ => Repeat::Finite(repeat_int as u16),
    };

    let extra = matches.get_flag("extra");
    let motion_quality = matches.get_one::<u8>("motion-quality").copied();
    let lossy_quality = matches.get_one::<u8>("lossy-quality").copied();
    let fast = matches.get_flag("fast");
    let settings = Settings {
        width,
        height,
        quality: matches.get_one::<u8>("quality").copied().unwrap_or(100),
        fast,
        repeat,
    };
    let quiet = matches.get_flag("quiet") || output_path == DestPath::Stdout;
    let fps: f32 = matches.get_one::<f32>("fps").copied().ok_or("?")?;
    let speed: f32 = matches.get_one::<f32>("fast-forward").copied().ok_or("?")?;
    let fixed_colors = matches.get_many::<Vec<rgb::RGB8>>("fixed-color");
    let matte = matches.get_one::<rgb::RGB8>("matte");

    let rate = source::Fps { fps, speed };

    if settings.quality < 20 {
        if settings.quality < 1 {
            return Err("Quality too low".into());
        } else if !quiet {
            eprintln!("warning: quality {} will give really bad results", settings.quality);
        }
    } else if settings.quality > 100 {
        return Err("Quality 100 is maximum".into());
    }

    if speed > 1000.0 || speed <= 0.0 {
        return Err("Fast-forward must be 0..1000".into());
    }

    if fps > 100.0 || fps <= 0.0 {
        return Err("100 fps is maximum".into());
    }
    else if !quiet && fps > 50.0 {
        eprintln!("warning: web browsers support max 50 fps");
    }

    check_if_paths_exist(&frames)?;

    let mut decoder = if let [path] = &frames[..] {
        match file_type(path).unwrap_or(FileType::Other) {
            FileType::PNG | FileType::JPEG => return Err("Only a single image file was given as an input. This is not enough to make an animation.".into()),
            FileType::GIF => {
                if !quiet && (width.is_none() && settings.quality > 50) {
                    eprintln!("warning: reading an existing GIF as an input. This can only worsen the quality. Use PNG frames instead.");
                }
                Box::new(gif::GifDecoder::new(path, rate)?)
            },
            _ if path.is_dir() => {
                return Err(format!("{} is a directory, not a PNG file", path.display()).into());
            },
            FileType::Other => get_video_decoder(path, rate, settings)?,
        }
    } else {
        if let Ok(FileType::JPEG) = file_type(&frames[0]) {
            return Err("JPEG format is unsuitable for conversion to GIF.\n\n\
                JPEG's compression artifacts and color space are very problematic for palette-based\n\
                compression. Please don't use JPEG for making GIF animations. Please re-export\n\
                your animation using the PNG format.".into())
        }
        if speed != 1.0 {
            return Err("Speed is for videos. It doesn't make sense for images. Use fps only".into());
        }
        Box::new(png::Lodecoder::new(frames, rate))
    };

    let mut pb;
    let mut nopb = NoProgress {};
    let progress: &mut dyn ProgressReporter = if quiet {
        &mut nopb
    } else {
        pb = ProgressBar::new(decoder.total_frames());
        &mut pb
    };

    let (mut collector, mut writer) = gifski::new(settings)?;
    if let Some(fixed_colors) = fixed_colors {
        for f in fixed_colors.flatten() {
            writer.add_fixed_color(*f);
        }
    }
    if let Some(matte) = matte {
        #[allow(deprecated)]
        writer.set_matte_color(*matte);
    }
    if extra {
        #[allow(deprecated)]
        writer.set_extra_effort(true);
    }
    if let Some(motion_quality) = motion_quality {
        #[allow(deprecated)]
        writer.set_motion_quality(motion_quality);
    }
    if let Some(lossy_quality) = lossy_quality {
        #[allow(deprecated)]
        writer.set_lossy_quality(lossy_quality);
    }

    let decode_thread = thread::Builder::new().name("decode".into()).spawn(move || {
        decoder.collect(&mut collector)
    })?;

    let mut file_tmp;
    let mut stdio_tmp;
    let out: &mut dyn io::Write = match output_path {
        DestPath::Path(p) => {
            file_tmp = File::create(p)
                .map_err(|e| format!("Can't write to {}: {e}", p.display()))?;
            &mut file_tmp
        },
        DestPath::Stdout => {
            stdio_tmp = io::stdout().lock();
            &mut stdio_tmp
        },
    };
    writer.write(io::BufWriter::new(out), progress)?;
    decode_thread.join().map_err(|_| "thread died?")??;
    progress.done(&format!("gifski created {output_path}"));

    Ok(())
}

fn parse_color(c: &str) -> Result<rgb::RGB8, String> {
    let c = c.trim_matches(|c:char| c.is_ascii_whitespace());
    let c = c.strip_prefix('#').unwrap_or(c);

    if c.len() != 6 {
        return Err(format!("color must be 6-char hex format, not '{c}'"));
    }
    let mut c = c.as_bytes().chunks_exact(2)
        .map(|c| u8::from_str_radix(std::str::from_utf8(c).unwrap_or_default(), 16).map_err(|e| e.to_string()));
    Ok(rgb::RGB8::new(
        c.next().ok_or_else(String::new)??,
        c.next().ok_or_else(String::new)??,
        c.next().ok_or_else(String::new)??,
    ))
}

fn parse_colors(colors: &str) -> Result<Vec<rgb::RGB8>, String> {
    colors.split(|c:char| c == ' ' || c == ',')
        .filter(|c| !c.is_empty())
        .map(parse_color)
        .collect()
}

#[test]
fn color_parser() {
    assert_eq!(parse_colors("#123456 78abCD,, ,").unwrap(), vec![rgb::RGB8::new(0x12,0x34,0x56), rgb::RGB8::new(0x78,0xab,0xcd)]);
    assert!(parse_colors("#12345").is_err());
}

#[allow(clippy::upper_case_acronyms)]
enum FileType {
    PNG, GIF, JPEG, Other,
}

fn file_type(path: &Path) -> BinResult<FileType> {
    let mut file = std::fs::File::open(path)?;
    let mut buf = [0; 4];
    file.read_exact(&mut buf)?;

    if &buf == b"\x89PNG" {
        return Ok(FileType::PNG);
    }
    if &buf == b"GIF8" {
        return Ok(FileType::GIF);
    }
    if buf[..2] == [0xFF, 0xD8] {
        return Ok(FileType::JPEG);
    }
    Ok(FileType::Other)
}

fn check_if_paths_exist(paths: &[PathBuf]) -> BinResult<()> {
    for path in paths {
        if !path.exists() {
            let mut msg = format!("Unable to find the input file: \"{}\"", path.display());
            if path.to_str().map_or(false, |p| p.contains(['*','?','['])) {
                msg += "\nThe pattern did not match any files.";
            } else if path.extension() == Some("gif".as_ref()) {
                msg = format!("Did you mean to use -o \"{}\" to specify it as the output file instead?", path.display());
            } else if path.is_relative() {
                use std::fmt::Write;
                write!(&mut msg, " (searched in \"{}\")", env::current_dir()?.display())?;
            }
            return Err(msg.into())
        }
    }
    Ok(())
}

#[derive(PartialEq)]
enum DestPath<'a> {
    Path(&'a Path),
    Stdout,
}

impl<'a> DestPath<'a> {
    pub fn new(path: &'a Path) -> Self {
        if path.as_os_str() == "-" {
            Self::Stdout
        } else {
            Self::Path(Path::new(path))
        }
    }
}

impl fmt::Display for DestPath<'_> {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Self::Path(orig_path) => {
                let abs_path = dunce::canonicalize(orig_path);
                abs_path.as_ref().map(|p| p.as_path()).unwrap_or(orig_path).display().fmt(f)
            },
            Self::Stdout => f.write_str("stdout"),
        }
    }
}

#[cfg(feature = "video")]
fn get_video_decoder(path: &Path, fps: source::Fps, settings: Settings) -> BinResult<Box<dyn Source + Send>> {
    Ok(Box::new(ffmpeg_source::FfmpegDecoder::new(path, fps, settings)?))
}

#[cfg(not(feature = "video"))]
#[cold]
fn get_video_decoder(_: &Path, _: source::Fps, _: Settings) -> BinResult<Box<dyn Source + Send>> {
    Err(r"Video support is permanently disabled in this executable.

To enable video decoding you need to recompile gifski from source with:
cargo build --release --features=video
or
cargo install gifski --features=video

Alternatively, use ffmpeg command to export PNG frames, and then specify
the PNG files as input for this executable. Instructions on https://gif.ski
".into())
}

struct ProgressBar {
    pb: pbr::ProgressBar<Stdout>,
    frames: u64,
    total: Option<u64>,
    previous_estimate: u64,
    displayed_estimate: u64,
}
impl ProgressBar {
    fn new(total: Option<u64>) -> Self {
        let mut pb = pbr::ProgressBar::new(total.unwrap_or(100));
        pb.show_speed = false;
        pb.show_percent = false;
        pb.format(" #_. ");
        pb.message("Frame ");
        pb.set_max_refresh_rate(Some(Duration::from_millis(250)));
        Self {
            pb, frames: 0, total, previous_estimate: 0, displayed_estimate: 0,
        }
    }
}

impl ProgressReporter for ProgressBar {
    fn increase(&mut self) -> bool {
        self.frames += 1;
        if self.total.is_none() {
            self.pb.total = (self.frames + 50).max(100);
        }
        self.pb.inc();
        true
    }

    fn written_bytes(&mut self, bytes: u64) {
        let min_frames = self.total.map_or(10, |t| (t / 16).clamp(5, 50));
        if self.frames > min_frames {
            let total_size = bytes * self.pb.total / self.frames;
            let new_estimate = if total_size >= self.previous_estimate { total_size } else { (self.previous_estimate + total_size) / 2 };
            self.previous_estimate = new_estimate;
            if self.displayed_estimate.abs_diff(new_estimate) > new_estimate/10 {
                self.displayed_estimate = new_estimate;
                let (num, unit, x) = if new_estimate > 1_000_000 {
                    (new_estimate as f64/1_000_000., "MB", if new_estimate > 10_000_000 {0} else {1})
                } else {
                    (new_estimate as f64/1_000., "KB", 0)
                };
                self.pb.message(&format!("{num:.x$}{unit} GIF; Frame "));
            }
        }
    }

    fn done(&mut self, msg: &str) {
        self.pb.finish_print(msg);
    }
}
