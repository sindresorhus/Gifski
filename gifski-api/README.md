# [<img width="100%" src="https://gif.ski/gifski.svg" alt="gif.ski">](https://gif.ski)

Highest-quality GIF encoder based on [pngquant](https://pngquant.org).

**[gifski](https://gif.ski)** converts video frames to GIF animations using pngquant's fancy features for efficient cross-frame palettes and temporal dithering. It produces animated GIFs that use thousands of colors per frame.

![(CC) Blender Foundation | gooseberry.blender.org](https://gif.ski/demo.gif)

It's a CLI tool, but it can also be compiled [as a C library](https://docs.rs/gifski) for seamless use in other apps.

## Download and install

See [releases](https://github.com/ImageOptim/gifski/releases) page for executables.

If you have [Homebrew](https://brew.sh/), you can also get it with `brew install gifski`.

If you have [Rust from rustup](https://www.rust-lang.org/install.html) (1.63+), you can also build it from source with [`cargo install gifski`](https://lib.rs/crates/gifski).

## Usage

gifski is a command-line tool. If you're not comfortable with a terminal, try the GUI version for [Windows][winmsi] or for [macOS][macapp].

[winmsi]: https://github.com/ImageOptim/gifski/releases/download/1.14.4/gifski_1.14.4_x64_en-US.msi
[macapp]: https://sindresorhus.com/gifski

### From ffmpeg video

> Tip: Instead of typing file paths, you can drag'n'drop files into the terminal window!

If you have ffmpeg installed, you can use it to stream a video directly to the gifski command by adding `-f yuv4mpegpipe` to `ffmpeg`'s arguments:

```sh
ffmpeg -i video.mp4 -f yuv4mpegpipe - | gifski -o anim.gif -
```

Replace "video.mp4" in the above code with actual path to your video.

Note that there's `-` at the end of the command. This tells `gifski` to read from standard input. Reading a `.y4m` file from disk would work too, but these files are huge.

`gifski` may automatically downsize the video if it has resolution too high for a GIF. Use `--width=1280` if you can tolerate getting huge file sizes.

### From PNG frames

A directory full of PNG frames can be used as an input too. You can export them from any animation software. If you have `ffmpeg` installed, you can also export frames with it:

```sh
ffmpeg -i video.webm frame%04d.png
```

and then make the GIF from the frames:

```sh
gifski -o anim.gif frame*.png
```

Note that `*` is a special wildcard character, and it won't work when placed inside quoted string (`"*"`).

You can also resize frames (with `-W <width in pixels>` option). If the input was ever encoded using a lossy video codec it's recommended to at least halve size of the frames to hide compression artefacts and counter chroma subsampling that was done by the video codec.

See `gifski --help` for more options.

### Tips for smaller GIF files

Expect to lose a lot of quality for little gain. GIF just isn't that good at compressing, no matter how much you compromise.

* Use `--width` and `--height` to make the animation smaller. This makes the biggest difference.
* Add `--quality=80` (or a lower number) to lower overall quality. You can fine-tune the quality with:
    * `--lossy-quality=60` lower values make animations noisier/grainy, but reduce file sizes.
    * `--motion-quality=60` lower values cause smearing or banding in frames with motion, but reduce file sizes.

If you need to make a GIF that fits a predefined file size, you have to experiment with different sizes and quality settings. The command line tool will display estimated total file size during compression, but keep in mind that the estimate is very imprecise.

## Building

1. [Install Rust via rustup](https://www.rust-lang.org/en-US/install.html). This project only supports up-to-date versions of Rust. You may get errors about "unstable" features if your compiler version is too old. Run `rustup update`.
2. Clone the repository: `git clone https://github.com/ImageOptim/gifski`
3. In the cloned directory, run: `cargo build --release`. This will build in `./target/release`.

### Using from C

[See `gifski.h`](https://github.com/ImageOptim/gifski/blob/main/gifski.h) for [the C API](https://docs.rs/gifski/latest/gifski/c_api/#functions). To build the library, run:

```sh
rustup update
cargo build --release
```

and link with `target/release/libgifski.a`. Please observe the [LICENSE](LICENSE).

### C dynamic library for package maintainers

The build process uses [`cargo-c`](https://lib.rs/cargo-c) for building the dynamic library correctly and generating the pkg-config file.

```sh
rustup update
cargo install cargo-c
# build
cargo cbuild --prefix=/usr --release
# install
cargo cinstall --prefix=/usr --release --destdir=pkgroot
```

The `cbuild` command can be omitted, since `cinstall` will trigger a build if it hasn't been done already.

## License

AGPL 3 or later. I can offer alternative licensing options, including [commercial licenses](https://supso.org/projects/pngquant). Let [me](https://kornel.ski/contact) know if you'd like to use it in a product incompatible with this license.

## With built-in video support

The tool optionally supports decoding video directly, but unfortunately it relies on ffmpeg 6.x, which may be *very hard* to get working, so it's not enabled by default.

You must have `ffmpeg` and `libclang` installed, both with their C headers installed in default system include paths. Details depend on the platform and version, but you usually need to install packages such as `libavformat-dev`, `libavfilter-dev`, `libavdevice-dev`, `libclang-dev`, `clang`. Please note that installation of these dependencies may be quite difficult. Especially on macOS and Windows it takes *expert knowledge* to just get them installed without wasting several hours on endless stupid installation and compilation errors, which I can't help with. If you're cross-compiling, try uncommenting `[patch.crates-io]` section at the end of `Cargo.toml`, which includes some experimental fixes for ffmpeg.

Once you have dependencies installed, compile with `cargo build --release --features=video` or `cargo build --release --features=video-static`.

When compiled with video support [ffmpeg licenses](https://www.ffmpeg.org/legal.html) apply. You may need to have a patent license to use H.264/H.265 video (I recommend using VP9/WebM instead).

```sh
gifski -o out.gif video.mp4
```

## Cross-compilation for iOS

The easy option is to use the included `gifski.xcodeproj` file to build the library automatically for all Apple platforms. Add it as a [subproject](https://lib.rs/crates/cargo-xcode) to your Xcode project, and link with `gifski-staticlib` Xcode target. See [the GUI app](https://github.com/sindresorhus/Gifski) for an example how to integrate the library.

### Cross-compilation for iOS manually

Make sure you have Rust installed via [rustup](https://rustup.rs/). Run once:

```sh
rustup target add aarch64-apple-ios
```

and then to build the library:

```sh
rustup update
cargo build --lib --release --target=aarch64-apple-ios
```

The build may print "dropping unsupported crate type `cdylib`" warning. This is expected when building for iOS.

This will create a static library in `./target/aarch64-apple-ios/release/libgifski.a`. You can add this library to your Xcode project. See [gifski.app](https://github.com/sindresorhus/Gifski) for an example how to use libgifski from Swift.

