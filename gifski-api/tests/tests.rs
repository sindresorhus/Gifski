use rgb::ComponentMap;
use std::path::{Path, PathBuf};
use imgref::ImgVec;
use imgref::{ImgRef, ImgRefMut};
use rgb::RGBA8;
use gifski::{Settings, new, progress};

#[test]
fn n_frames() {
    for num_frames in 1..=11 {
        assert_anim_eq(num_frames, frame_filename, None, 0.8);
    }
}

fn assert_anim_eq(num_frames: usize, frame_filename: fn(usize) -> PathBuf, frame_edit: Option<fn(usize, ImgRefMut<RGBA8>)>, max_diff: f64) {
    let (c, w) = new(Settings::default()).unwrap();

    let t = std::thread::spawn(move || {
        for n in 0..num_frames {
            let pts = if num_frames == 1 { 0.1 } else { n as f64 / 10. };
            let name = frame_filename(n);
            if let Some(frame_edit) = frame_edit {
                let mut frame = load_frame(&name);
                frame_edit(n, frame.as_mut());
                c.add_frame_rgba(n, frame, pts).unwrap();
            } else {
                c.add_frame_png_file(n, name, pts).unwrap();
            }
        }
    });

    let mut out = Vec::new();
    w.write(&mut out, &mut progress::NoProgress {}).unwrap();
    t.join().unwrap();

    // std::fs::write(format!("/tmp/anim{num_frames}{max_diff}{}.png", frame_edit.is_some()), &out);

    let mut n = 0;
    let mut frames_seen = 0;
    for_each_frame(&out, |delay, _, actual| {
        frames_seen += 1;
        let next_n = delay as usize / 10;
        while n < next_n {
            let name = frame_filename(n);
            let mut expected = load_frame(&name);
            if let Some(frame_edit) = frame_edit {
                frame_edit(n, expected.as_mut());
            }
            assert_images_eq(expected.as_ref(), actual, max_diff, format_args!("n={n}/{num_frames}, {delay}/{next_n}, {}", name.display()));
            n += 1;
        }
    });
    assert!(n == num_frames, "{frames_seen} : {num_frames}");
}

fn load_frame(name: &Path) -> ImgVec<RGBA8> {
    let img = lodepng::decode32_file(name).unwrap();
    ImgVec::new(img.buffer, img.width, img.height)
}

#[test]
fn all_dupe_frames() {
    let (c, w) = new(Settings::default()).unwrap();

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
    for_each_frame(&out, |delay, frame, actual| {
        let expected = lodepng::decode32_file(frame_filename(1)).unwrap();
        let expected = ImgVec::new(expected.buffer, expected.width, expected.height);
        assert_images_eq(expected.as_ref(), actual, 0., format_args!("n={n}, {delay} "));
        delays.push(frame.delay);
        n += 1;
    });
    assert_eq!(delays, [130]);
}

#[test]
fn all_but_one_dupe_frames() {
    let (c, w) = new(Settings::default()).unwrap();

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
    for_each_frame(&out, |delay, frame, actual| {
        let name = frame_filename(if n == 0 {0} else {1});
        let expected = lodepng::decode32_file(&name).unwrap();
        let expected = ImgVec::new(expected.buffer, expected.width, expected.height);
        assert_images_eq(expected.as_ref(), actual, 1.7, format_args!("n={n}, {delay} {}", name.display()));
        delays.push(frame.delay);
        n += 1;
    });
    assert_eq!(delays, [120, 20]);
}

fn frame_filename(n: usize) -> PathBuf {
    format!("tests/{}.png", (n%3)+1).into()
}

fn for_each_frame(mut gif_data: &[u8], mut cb: impl FnMut(u32, &gif::Frame, ImgRef<RGBA8>)) {
    let mut gif_opts = gif::DecodeOptions::new();
    gif_opts.set_color_output(gif::ColorOutput::Indexed);
    let mut decoder = gif_opts.read_info(&mut gif_data).unwrap();
    let mut screen = gif_dispose::Screen::new_decoder(&decoder);

    let mut delay = 0;
    while let Some(frame) = decoder.read_next_frame().unwrap() {
        screen.blit_frame(frame).unwrap();
        delay += frame.delay as u32;
        cb(delay, frame, screen.pixels_rgba());
    }
}


#[test]
fn anim3() {
    assert_anim_eq(6*3, |n| format!("tests/a3/{}{}.png", ["x","y","z"][n/6], n%6).into(), None, 0.8);
}

#[test]
fn anim3_transparent1() {
    assert_anim_eq(6*3, |n| format!("tests/a3/{}{}.png", ["x","y","z"][n/6], n%6).into(), Some(|_,mut fr| {
        fr.pixels_mut().for_each(|px| if px.r == 0 && px.g == 0 { px.a = 0; })
    }), 0.8);
}

#[test]
fn anim3_transparent2() {
    assert_anim_eq(6*3, |n| format!("tests/a3/{}{}.png", ["x","y","z"][n/6], n%6).into(), Some(|_,mut fr| {
        fr.pixels_mut().for_each(|px| if px.r != 0 { px.a = 0; })
    }), 0.8);
}

#[test]
fn anim3_twitch() {
    assert_anim_eq(6*3*3, |x| {
        let n = (x/3) ^ (x&1);
        format!("tests/a3/{}{}.png", ["x","y","z"][n/6], n%6).into()
    }, None, 0.8);
}

#[test]
fn anim3_mix() {
    assert_anim_eq(6*3*3, |x| {
        let n = (x/3) ^ (x&3);
        format!("tests/a3/{}{}.png", ["x","y","z"][(n/6)%3], n%6).into()
    }, Some(|n, mut fr| {
        fr.pixels_mut().take(12).for_each(|px| {
            px.g = px.g.wrapping_add(n as _);
        });
    }), 2.);
}

#[test]
fn anim2_fwd() {
    assert_anim_eq(43, |n| format!("tests/a2/{:02}.png", 1+n).into(), None, 0.8);
}

#[test]
fn anim2_rev() {
    assert_anim_eq(43, |n| format!("tests/a2/{:02}.png", 43-n).into(), None, 0.8);
}

#[test]
fn anim2_dupes() {
    assert_anim_eq(43*2, |n| format!("tests/a2/{:02}.png", 1+n/2).into(), None, 0.8);
}

#[test]
fn anim2_flips() {
    assert_anim_eq(43*2, |n| format!("tests/a2/{:02}.png", if n&1==0 { 10 } else { 1+n/2 }).into(), None, 0.8);
}


#[test]
fn anim2_transparent() {
    assert_anim_eq(43, |n| format!("tests/a2/{:02}.png", 1+n).into(), Some(|_, mut fr| {
        fr.pixels_mut().for_each(|px| if px.r > 128 { px.a = 0; })
    }), 0.8);
}

#[test]
fn anim2_transparent2() {
    assert_anim_eq(43, |n| format!("tests/a2/{:02}.png", 43-n).into(), Some(|_, mut fr| {
        fr.pixels_mut().for_each(|px| if px.g > 200 { px.a = 0; })
    }), 0.8);
}

#[test]
fn anim2_transparent_half() {
    assert_anim_eq(43, |n| format!("tests/a2/{:02}.png", 43-n).into(), Some(|_, mut fr| {
        let n = fr.width()*(fr.height()/2);
        fr.pixels_mut().skip(n).for_each(|px| if px.g > 200 { px.a = 0; })
    }), 0.8);
}

#[track_caller]
fn assert_images_eq(a: ImgRef<RGBA8>, b: ImgRef<RGBA8>, max_diff: f64, msg: impl std::fmt::Display) {
    let diff = a.pixels().zip(b.pixels()).map(|(a,b)| {
        if a.a != b.a {
            return 300000;
        }
        if a.a == 0 {
            return 0;
        }
        let a = a.map(i32::from);
        let b = b.map(i32::from);
        let d = a - b;
        (d.r * d.r * 2 +
         d.g * d.g * 3 +
         d.b * d.b) as u64
    }).sum::<u64>() as f64 / (a.width() * a.height() * 3) as f64;
    if diff > max_diff {
        dump("expected", a);
        dump("actual", b);
    }
    assert!(diff <= max_diff, "{diff} diff > {max_diff} {msg}");
}

fn dump(filename: &str, px: ImgRef<RGBA8>) {
    let (buf, w, h) = px.to_contiguous_buf();
    lodepng::encode32_file(format!("/tmp/gifski-test-{filename}.png"), &buf, w, h).unwrap();
}
