#[macro_use] extern crate clap;

use std::ffi::OsStr;
use std::io::Read;
use gifski::{Settings, Repeat};

#[cfg(feature = "video")]
mod ffmpeg_source;
mod png;
mod source;
use crate::source::*;

use gifski::progress::{NoProgress, ProgressBar, ProgressReporter};

pub type BinResult<T, E = Box<dyn std::error::Error + Send + Sync>> = Result<T, E>;

use clap::{App, AppSettings, Arg};

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
const VIDEO_FRAMES_ARG_HELP: &str = "PNG image files";

fn main() {
    if let Err(e) = bin_main() {
        eprintln!("error: {}", e);
        if let Some(e) = e.source() {
            eprintln!("error: {}", e);
        }
        std::process::exit(1);
    }
}

#[allow(clippy::float_cmp)]
fn bin_main() -> BinResult<()> {
    let matches = App::new(crate_name!())
                        .version(crate_version!())
                        .about("https://gif.ski by Kornel Lesiński")
                        .setting(AppSettings::DeriveDisplayOrder)
                        .setting(AppSettings::ArgRequiredElseHelp)
                        .setting(AppSettings::AllowNegativeNumbers)
                        .arg(Arg::new("output")
                            .long("output")
                            .short('o')
                            .help("Destination file to write to; \"-\" means stdout")
                            .forbid_empty_values(true)
                            .takes_value(true)
                            .value_name("a.gif")
                            .required(true))
                        .arg(Arg::new("fps")
                            .long("fps")
                            .short('r')
                            .help("Frame rate of animation. If using PNG files as \
                                   input, this means the speed, as all frames are \
                                   kept. If video is used, it will be resampled to \
                                   this constant rate by dropping and/or duplicating \
                                   frames")
                            .forbid_empty_values(true)
                            .value_name("num")
                            .default_value("20"))
                        .arg(Arg::new("fast-forward")
                            .long("fast-forward")
                            .help("Multiply speed of video by a factor\n(no effect when using images as input)")
                            .forbid_empty_values(true)
                            .value_name("x")
                            .default_value("1"))
                        .arg(Arg::new("fast")
                            .long("fast")
                            .help("50% faster encoding, but 10% worse quality and larger file size"))
                        .arg(Arg::new("extra")
                            .long("extra")
                            .conflicts_with("fast")
                            .help("50% slower encoding, but 1% better quality"))
                        .arg(Arg::new("quality")
                            .long("quality")
                            .short('Q')
                            .value_name("1-100")
                            .takes_value(true)
                            .default_value("90")
                            .help("Lower quality may give smaller file"))
                        .arg(Arg::new("width")
                            .long("width")
                            .short('W')
                            .takes_value(true)
                            .value_name("px")
                            .help("Maximum width.\nBy default anims are limited to about 800x600"))
                        .arg(Arg::new("height")
                            .long("height")
                            .short('H')
                            .takes_value(true)
                            .value_name("px")
                            .help("Maximum height (stretches if the width is also set)"))
                        .arg(Arg::new("nosort")
                            .alias("nosort")
                            .long("no-sort")
                            .help("Use files exactly in the order given, rather than sorted"))
                        .arg(Arg::new("quiet")
                            .long("quiet")
                            .short('q')
                            .help("Do not display anything on standard output/console"))
                        .arg(Arg::new("FILE")
                            .help(VIDEO_FRAMES_ARG_HELP)
                            .min_values(1)
                            .forbid_empty_values(true)
                            .use_delimiter(false)
                            .required(true))
                        .arg(Arg::new("repeat")
                            .long("repeat")
                            .help("Number of times the animation is repeated (-1 none, 0 forever or <value> repetitions")
                            .takes_value(true)
                            .value_name("num"))
                        .get_matches_from(wild::args_os());

    let mut frames: Vec<_> = matches.values_of("FILE").ok_or("Missing files")?.collect();
    if !matches.is_present("nosort") {
        frames.sort_by(|a, b| natord::compare(a, b));
    }
    let frames: Vec<_> = frames.into_iter().map(PathBuf::from).collect();

    let output_path = DestPath::new(matches.value_of_os("output").ok_or("Missing output")?);
    let width = parse_opt(matches.value_of("width")).map_err(|_| "Invalid width")?;
    let height = parse_opt(matches.value_of("height")).map_err(|_| "Invalid height")?;
    let repeat_int = parse_opt(matches.value_of("repeat")).map_err(|_| "Invalid repeat count")?.unwrap_or(0) as i16;
    let repeat;
    match repeat_int {
        -1 => repeat = Repeat::Finite(0),
        0 => repeat = Repeat::Infinite,
        _ => repeat = Repeat::Finite(repeat_int as u16),
    }

    let extra = matches.is_present("extra");
    let settings = Settings {
        width,
        height,
        quality: parse_opt(matches.value_of("quality")).map_err(|_| "Invalid quality")?.unwrap_or(100),
        fast: matches.is_present("fast"),
        repeat,
    };
    let quiet = matches.is_present("quiet") || output_path == DestPath::Stdout;
    let fps: f32 = matches.value_of("fps").ok_or("Missing fps")?.parse().map_err(|_| "FPS must be a number")?;
    let speed: f32 = matches.value_of("fast-forward").ok_or("Missing speed")?.parse().map_err(|_| "Speed must be a number")?;

    let rate = source::Fps { speed, fps };

    if settings.quality < 20 {
        if settings.quality < 1 {
            return Err("Quality too low".into());
        } else if !quiet {
            eprintln!("warning: quality {} will give really bad results", settings.quality);
        }
    } else if settings.quality > 100 {
        return Err("Quality 100 is maximum".into());
    }

    if fps > 100.0 {
        return Err("100 fps is maximum".into());
    }
    else if !quiet && fps > 50.0 {
        eprintln!("warning: web browsers support max 50 fps");
    }

    check_if_paths_exist(&frames)?;

    let mut decoder = if frames.is_empty() {
        return Err("Please specify input files".into())
    } else if frames.len() == 1 {
        match file_type(&frames[0]).unwrap_or(FileType::Other) {
            FileType::PNG | FileType::JPEG => return Err("Only a single image file was given as an input. This is not enough to make an animation.".into()),
            _ => get_video_decoder(&frames[0], rate, settings)?,
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
        Box::new(png::Lodecoder::new(frames, &rate))
    };

    let mut pb;
    let mut nopb = NoProgress {};
    let progress: &mut dyn ProgressReporter = if quiet {
        &mut nopb
    } else {
        pb = ProgressBar::new(decoder.total_frames());
        pb.show_speed = false;
        pb.show_percent = false;
        pb.format(" #_. ");
        pb.message("Frame ");
        pb.set_max_refresh_rate(Some(Duration::from_millis(250)));
        &mut pb
    };

    let (mut collector, mut writer) = gifski::new(settings)?;
    if extra {
        #[allow(deprecated)]
        writer.set_extra_effort();
    }
    let decode_thread = thread::Builder::new().name("decode".into()).spawn(move || {
        decoder.collect(&mut collector)
    })?;

    match output_path {
        DestPath::Path(p) => {
            let file = File::create(p)
                .map_err(|e| format!("Can't write to {}: {}", p.display(), e))?;
            writer.write(file, progress)?;
        },
        DestPath::Stdout => {
            writer.write(io::stdout().lock(), progress)?;
        },
    };
    decode_thread.join().map_err(|_| "thread died?")??;
    progress.done(&format!("gifski created {}", output_path));

    Ok(())
}

enum FileType {
    PNG, JPEG, Other,
}

fn file_type(path: &Path) -> BinResult<FileType> {
    let mut file = std::fs::File::open(path)?;
    let mut buf = [0; 4];
    file.read_exact(&mut buf)?;

    if &buf == b"\x89PNG" {
        return Ok(FileType::PNG);
    }
    if &buf[..2] == [0xFF, 0xD8] {
        return Ok(FileType::JPEG);
    }
    Ok(FileType::Other)
}

fn check_if_paths_exist(paths: &[PathBuf]) -> BinResult<()> {
    for path in paths {
        if !path.exists() {
            let mut msg = format!("Unable to find the input file: \"{}\"", path.display());
            if path.to_str().map_or(false, |p| p.contains('*')) {
                msg += "\nThe path contains a literal \"*\" character. If you want to select multiple files, don't put the special wildcard characters in quotes.";
            } else if path.is_relative() {
                msg += &format!(" (searched in \"{}\")", env::current_dir()?.display());
            }
            return Err(msg.into())
        }
    }
    Ok(())
}

fn parse_opt<T: ::std::str::FromStr<Err = ::std::num::ParseIntError>>(s: Option<&str>) -> BinResult<Option<T>> {
    match s {
        Some(s) => Ok(Some(s.parse()?)),
        None => Ok(None),
    }
}

#[derive(PartialEq)]
enum DestPath<'a> {
    Path(&'a Path),
    Stdout,
}

impl<'a> DestPath<'a> {
    pub fn new(path: &'a OsStr) -> Self {
        if path == "-" {
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
