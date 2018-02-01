# [<img width="100%" src="https://gif.ski/gifski.svg" alt="gif.ski">](https://gif.ski)

Highest-quality GIF encoder based on [pngquant](https://pngquant.org).

**[gifski](https://gif.ski)** converts video frames to GIF animations using pngquant's fancy features for efficient cross-frame palettes and temporal dithering. It produces animated GIFs that use thousands of colors per frame.

![(CC) Blender Foundation | gooseberry.blender.org](https://gif.ski/demo.gif)

It's a CLI tool, but it can also be compiled [as a library](https://docs.rs/gifski) for seamelss use in other apps.

## Download and install

See [releases](https://github.com/ImageOptim/gifski/releases) page for executables.

If you have [Rust](https://www.rust-lang.org/install.html), you can also get it with `cargo install gifski`. Run `cargo build --release --features=openmp` to build from source.

If you have [Homebrew](https://brew.sh/), you can also get it with `brew install gifski`.

## Usage

You can use `ffmpeg` command to convert any video to PNG frames:

```sh
ffmpeg -i video.webm frame%04d.png
```

and then make the GIF from the frames:

```sh
gifski -o anim.gif frame*.png
```

You can also resize frames (with `-W <width in pixels>` option). If the input was ever encoded using a lossy video codec it's recommended to at least halve size of the frames to hide compression artefacts and counter chroma subsampling that was done by the video codec.

See `gifski -h` for more options.

The tool optionally supports decoding video directly. Note that pre-built binaries distributed from the website don't support video. It's only enabled if you compile it with `--features=video`:

```sh
gifski -o out.gif video.mp4
```

## License

AGPL 3 or later. Let [me](https://kornel.ski/contact) know if you'd like to use it in a product incompatible with this license. I can offer alternative licensing options.

## Building

1. [Install Rust](https://www.rust-lang.org/en-US/install.html)
2. Clone the repository: `git clone https://github.com/ImageOptim/gifski`
3. In the cloned directory, run: `cargo build --release`

Enable OpenMP by adding `--features=openmp` to Cargo build flags (supported on macOS and Linux with GCC). It makes encoding more than twice as fast.

### With built-in video support

Install `ffmpeg` and its dependencies (probably `libavformat-dev`, `libavfilter-dev`, `libavdevice-dev`, `libclang-dev`, `clang`).

Compile with `cargo build --release --features=video,openmp`.

When compiled with video support [ffmpeg licenses](https://www.ffmpeg.org/legal.html) apply. You may need to have a patent license to use H.264/H.265 video (I recommend using VP9/WebM instead).

### Using from C

See `gifski.h` for [the API](https://docs.rs/gifski). To build, run:

```sh
cargo build --release
```

and link with `target/release/libgifski.a`. Please observe the [LICENSE](LICENSE).

