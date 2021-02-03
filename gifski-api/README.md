# [<img width="100%" src="https://gif.ski/gifski.svg" alt="gif.ski">](https://gif.ski)

Highest-quality GIF encoder based on [pngquant](https://pngquant.org).

**[gifski](https://gif.ski)** converts video frames to GIF animations using pngquant's fancy features for efficient cross-frame palettes and temporal dithering. It produces animated GIFs that use thousands of colors per frame.

![(CC) Blender Foundation | gooseberry.blender.org](https://gif.ski/demo.gif)

It's a CLI tool, but it can also be compiled [as a C library](https://docs.rs/gifski) for seamless use in other apps.

## Download and install

See [releases](https://github.com/ImageOptim/gifski/releases) page for executables.

If you have [Rust](https://www.rust-lang.org/install.html) 1.49+, you can also get it with [`cargo install gifski`](https://crates.rs/crates/gifski). Run `cargo build --release --features=openmp` or `cargo build --release --features=video,openmp` to build from source.

If you have [Homebrew](https://brew.sh/), you can also get it with `brew install gifski`.

## Usage

gifski is a command-line tool. There is no GUI for Windows or Linux (there is one for [macOS](https://sindresorhus.com/gifski)).

The recommended way is to first export video as PNG frames. If you have `ffmpeg` installed, you can run in terminal:

```sh
ffmpeg -i video.webm frame%04d.png
```

and then make the GIF from the frames:

```sh
gifski -o anim.gif frame*.png
```

You can also resize frames (with `-W <width in pixels>` option). If the input was ever encoded using a lossy video codec it's recommended to at least halve size of the frames to hide compression artefacts and counter chroma subsampling that was done by the video codec.

Adding `--quality=90` may reduce file sizes a bit, but expect to lose a lot of quality for little gain. GIF just isn't that good at compressing, no matter how much you compromise.

See `gifski -h` for more options.

## Building

1. [Install Rust via rustup](https://www.rust-lang.org/en-US/install.html) or run `rustup update`. This project only supports up-to-date versions of Rust. You may get compile errors, warnings about "unstable edition", etc. if you don't run `rustup update` regularly.
2. Clone the repository: `git clone https://github.com/ImageOptim/gifski`
3. In the cloned directory, run: `cargo build --release`

Enable OpenMP by adding `--features=openmp` to Cargo build flags (supported on macOS and Linux with GCC). It makes encoding more than twice as fast.

### Using from C

[See `gifski.h` for the API](https://docs.rs/gifski). To build the library, run:

```sh
cargo build --release
```

and link with `target/release/libgifski.a`. Please observe the [LICENSE](LICENSE).

## License

AGPL 3 or later. Let [me](https://kornel.ski/contact) know if you'd like to use it in a product incompatible with this license. I can offer alternative licensing options, including [commercial licenses](https://supso.org/projects/pngquant).

## With built-in video support

The tool optionally supports decoding video directly, but unfortunately it relies on ffmpeg 4.x, which may be *very hard* to get working, so it's not enabled by default.

You must have `ffmpeg` and `libclang` installed, both with their C headers intalled in default system include paths. Details depend on the platform and version, but you usually need to install packages such as `libavformat-dev`, `libavfilter-dev`, `libavdevice-dev`, `libclang-dev`, `clang`. Please note that installation of these dependencies may be quite difficult. Especially on macOS and Windows it takes *expert knowledge* to just get them installed without wasting several hours on endless stupid installation and compilation errors, which I can't help with.

Once you have dependencies installed, compile with `cargo build --release --features=video,openmp` or `cargo build --release --features=video-static`.

When compiled with video support [ffmpeg licenses](https://www.ffmpeg.org/legal.html) apply. You may need to have a patent license to use H.264/H.265 video (I recommend using VP9/WebM instead).

```sh
gifski -o out.gif video.mp4
```

## Cross-compilation for iOS

Make sure you have Rust installed via [rustup](https://rustup.rs/). Run once:

```sh
rustup target add aarch64-apple-ios
```

and then to build the library:

```sh
cargo build --lib --release --target=aarch64-apple-ios
```

The build will print "dropping unsupported crate type `cdylib`". This is normal and expected.

This will create a static library in `./target/aarch64-apple-ios/release/libgifski.a`. You can add this library to your Xcode project. See [gifski.app](https://github.com/sindresorhus/Gifski) for an example how to use libgifski from Swift.

You can also [use `cargo lipo` command](https://lib.rs/crates/cargo-lipo) to integrate with Xcode project to have it built automatically.


