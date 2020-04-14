#[cfg(feature = "malloc")]
use std::alloc::System;

#[cfg(feature = "malloc")]
#[cfg_attr(feature = "malloc", global_allocator)]
static A: System = System;

#[macro_use] extern crate clap;

#[cfg(feature = "video")]
extern crate ffmpeg;

use natord;
use wild;

#[cfg(feature = "video")]
mod ffmpeg_source;
mod png;
mod source;
use crate::source::*;

use gifski::progress::{NoProgress, ProgressBar, ProgressReporter};

pub type BinResult<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

use clap::{App, AppSettings, Arg};

use std::env;
use std::fs::File;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

#[cfg(feature = "video")]
const VIDEO_FRAMES_ARG_HELP: &'static str = "one MP4/WebM video, or multiple PNG animation frames";
#[cfg(not(feature = "video"))]
const VIDEO_FRAMES_ARG_HELP: &'static str = "PNG animation frames";

fn main() {
    if let Err(e) = bin_main() {
        eprintln!("error: {}", e);
        if let Some(e) = e.source() {
            eprintln!("error: {}", e);
        }
        std::process::exit(1);
    }
}

fn bin_main() -> BinResult<()> {
     let matches = App::new(crate_name!())
                        .version(crate_version!())
                        .about("https://gif.ski by Kornel Lesiński")
                        .setting(AppSettings::UnifiedHelpMessage)
                        .setting(AppSettings::DeriveDisplayOrder)
                        .setting(AppSettings::ArgRequiredElseHelp)
                        .arg(Arg::with_name("output")
                            .long("output")
                            .short("o")
                            .help("Destination file to write to")
                            .empty_values(false)
                            .takes_value(true)
                            .value_name("a.gif")
                            .required(true))
                        .arg(Arg::with_name("fps")
                            .long("fps")
                            .help("Animation frames per second (for PNG frames only)")
                            .empty_values(false)
                            .value_name("num")
                            .default_value("20"))
                        .arg(Arg::with_name("fast")
                            .long("fast")
                            .help("3 times faster encoding, but 10% lower quality and bigger file"))
                        .arg(Arg::with_name("quality")
                            .long("quality")
                            .value_name("1-100")
                            .takes_value(true)
                            .help("Lower quality may give smaller file"))
                        .arg(Arg::with_name("width")
                            .long("width")
                            .short("W")
                            .takes_value(true)
                            .value_name("px")
                            .help("Maximum width"))
                        .arg(Arg::with_name("height")
                            .long("height")
                            .short("H")
                            .takes_value(true)
                            .value_name("px")
                            .help("Maximum height (if width is also set)"))
                        .arg(Arg::with_name("once")
                            .long("once")
                            .help("Do not loop the GIF"))
                        .arg(Arg::with_name("nosort")
                            .long("nosort")
                            .help("Use files exactly in the order given, rather than sorted"))
                        .arg(Arg::with_name("quiet")
                            .long("quiet")
                            .help("Do not show a progress bar"))
                        .arg(Arg::with_name("FRAMES")
                            .help(VIDEO_FRAMES_ARG_HELP)
                            .min_values(1)
                            .empty_values(false)
                            .use_delimiter(false)
                            .required(true))
                        .get_matches_from(wild::args_os());

    let mut frames: Vec<_> = matches.values_of("FRAMES").ok_or("Missing files")?.collect();
    if !matches.is_present("nosort") {
        frames.sort_by(|a, b| natord::compare(a, b));
    }
    let frames: Vec<_> = frames.into_iter().map(|s| PathBuf::from(s)).collect();

    let output_path = Path::new(matches.value_of_os("output").ok_or("Missing output")?);
    let settings = gifski::Settings {
        width: parse_opt(matches.value_of("width")).map_err(|_| "Invalid width")?,
        height: parse_opt(matches.value_of("height")).map_err(|_| "Invalid height")?,
        quality: parse_opt(matches.value_of("quality")).map_err(|_| "Invalid quality")?.unwrap_or(100),
        once: matches.is_present("once"),
        fast: matches.is_present("fast"),
    };
    let quiet = matches.is_present("quiet");
    let fps: f32 = matches.value_of("fps").ok_or("Missing fps")?.parse().map_err(|_| "FPS must be a number")?;

    if settings.quality < 20 {
        if settings.quality < 1 {
            Err("Quality too low")?;
        } else {
            eprintln!("warning: quality {} will give really bad results", settings.quality);
        }
    } else if settings.quality > 100 {
        Err("Quality 100 is maximum")?;
    }

    check_if_path_exists(&frames[0])?;

    let mut decoder = if frames.len() == 1 {
        get_video_decoder(&frames[0], fps)?
    } else {
        Box::new(png::Lodecoder::new(frames, fps))
    };

    let mut progress: Box<dyn ProgressReporter> = if quiet {
        Box::new(NoProgress {})
    } else {
        let mut pb = ProgressBar::new(decoder.total_frames());
        pb.show_speed = false;
        pb.show_percent = false;
        pb.format(" #_. ");
        pb.message("Frame ");
        pb.set_max_refresh_rate(Some(Duration::from_millis(250)));
        Box::new(pb)
    };

    let (collector, writer) = gifski::new(settings)?;
    let decode_thread = thread::spawn(move || {
        decoder.collect(collector)
    });

    let file = File::create(output_path)
        .map_err(|e| format!("Can't write to {}: {}", output_path.display(), e))?;
    writer.write(file, &mut *progress)?;
    decode_thread.join().unwrap()?;
    progress.done(&format!("gifski created {}", output_path.display()));

    Ok(())
}

fn check_if_path_exists(path: &Path) -> BinResult<()> {
    if path.exists() {
        Ok(())
    } else {
        let mut msg = format!("Unable to find the input file: \"{}\"", path.display());
        if path.to_str().map_or(false, |p| p.contains('*')) {
            msg += "\nThe path contains a literal \"*\" character. If you want to select multiple files, don't put the special wildcard characters in quotes.";
        } else if path.is_relative() {
            msg += &format!(" (searched in \"{}\")", env::current_dir()?.display());
        }
        Err(msg)?
    }
}

fn parse_opt<T: ::std::str::FromStr<Err = ::std::num::ParseIntError>>(s: Option<&str>) -> BinResult<Option<T>> {
    match s {
        Some(s) => Ok(Some(s.parse()?)),
        None => Ok(None),
    }
}

#[cfg(feature = "video")]
fn get_video_decoder(path: &Path, fps: f32) -> BinResult<Box<dyn Source + Send>> {
    Ok(Box::new(ffmpeg_source::FfmpegDecoder::new(path, fps)?))
}

#[cfg(not(feature = "video"))]
fn get_video_decoder(_: &Path, _fps: f32) -> BinResult<Box<dyn Source + Send>> {
    Err(r"Video support is permanently disabled in this executable.

To enable video decoding you need to recompile gifski from source with:
cargo build --release --features=video

Alternatively, use ffmpeg command to export PNG frames, and then specify
the PNG files as input for this executable.
")?
}
