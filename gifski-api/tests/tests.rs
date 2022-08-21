use rgb::ComponentMap;
use std::path::PathBuf;
use imgref::ImgVec;
use imgref::ImgRef;
use rgb::RGBA8;
use gifski::*;

#[test]
fn n_frames() {
    for num_frames in 1..=11 {
        let (mut c, w) = new(Settings::default()).unwrap();

        let t = std::thread::spawn(move || {
            for n in 0..num_frames {
                c.add_frame_png_file(n, frame_filename(n), n as f64 * 0.1).unwrap();
            }
        });

        let mut out = Vec::new();
        w.write(&mut out, &mut progress::NoProgress {}).unwrap();
        t.join().unwrap();

        let mut n = 0;
        for_each_frame(&out, |_, actual| {
            let expected = lodepng::decode32_file(frame_filename(n)).unwrap();
            let expected = ImgVec::new(expected.buffer, expected.width, expected.height);
            assert_images_eq(expected.as_ref(), actual, 0.31);
            n += 1;
        });
        assert_eq!(n, num_frames);
    }
}

#[test]
fn all_dupe_frames() {
    let (mut c, w) = new(Settings::default()).unwrap();

    let t = std::thread::spawn(move || {
        c.add_frame_png_file(0, frame_filename(1), 0.1).unwrap();
        c.add_frame_png_file(1, frame_filename(1), 1.2).unwrap();
        c.add_frame_png_file(2, frame_filename(1), 1.3).unwrap();
    });

    let mut out = Vec::new();
    w.write(&mut out, &mut progress::NoProgress {}).unwrap();
    t.join().unwrap();

    let mut n = 0;
    let mut delays = vec![];
    for_each_frame(&out, |frame, actual| {
        let expected = lodepng::decode32_file(frame_filename(1)).unwrap();
        let expected = ImgVec::new(expected.buffer, expected.width, expected.height);
        assert_images_eq(expected.as_ref(), actual, 0.);
        delays.push(frame.delay);
        n += 1;
    });
    assert_eq!(delays, [130]);
}

#[test]
fn all_but_one_dupe_frames() {
    let (mut c, w) = new(Settings::default()).unwrap();

    let t = std::thread::spawn(move || {
        c.add_frame_png_file(0, frame_filename(0), 0.0).unwrap();
        c.add_frame_png_file(1, frame_filename(1), 1.2).unwrap();
        c.add_frame_png_file(2, frame_filename(1), 1.3).unwrap();
    });

    let mut out = Vec::new();
    w.write(&mut out, &mut progress::NoProgress {}).unwrap();
    t.join().unwrap();

    let mut delays = vec![];
    let mut n = 0;
    for_each_frame(&out, |frame, actual| {
        let expected = lodepng::decode32_file(frame_filename(if n == 0 {0} else {1})).unwrap();
        let expected = ImgVec::new(expected.buffer, expected.width, expected.height);
        assert_images_eq(expected.as_ref(), actual, 0.25);
        delays.push(frame.delay);
        n += 1;
    });
    assert_eq!(delays, [120, 20]);
}

fn frame_filename(n: usize) -> PathBuf {
    format!("tests/{}.png", (n%3)+1).into()
}

fn for_each_frame(mut gif_data: &[u8], mut cb: impl FnMut(&gif::Frame, ImgRef<RGBA8>)) {
    let mut gif_opts = gif::DecodeOptions::new();
    gif_opts.set_color_output(gif::ColorOutput::Indexed);
    let mut decoder = gif_opts.read_info(&mut gif_data).unwrap();
    let mut screen = gif_dispose::Screen::new_decoder(&decoder);

    while let Some(frame) = decoder.read_next_frame().unwrap() {
        screen.blit_frame(frame).unwrap();
        cb(frame, screen.pixels.as_ref());
    }
}

#[track_caller]
fn assert_images_eq(a: ImgRef<RGBA8>, b: ImgRef<RGBA8>, max_diff: f64) {
    let diff = a.pixels().zip(b.pixels()).map(|(a,b)| {
        let a = a.map(|c| c as i32);
        let b = b.map(|c| c as i32);
        let d = a - b;
        (d.r * d.r +
         d.g * d.g +
         d.b * d.b) as u64
    }).sum::<u64>() as f64 / (a.width() * a.height()) as f64;
    assert!(diff <= max_diff, "{} diff > {}", diff, max_diff);
}
