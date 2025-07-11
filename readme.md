<div align="center">
	<img src="Stuff/AppIcon-readme.png" width="200" height="200">
	<h1>Gifski</h1>
	<p>
		<b>Convert videos to high-quality GIFs on your Mac</b>
	</p>
	<br>
	<br>
	<br>
</div>

This is a macOS app for the [`gifski` encoder](https://gif.ski), which converts videos to GIF animations using [`pngquant`](https://pngquant.org)'s fancy features for efficient cross-frame palettes and temporal dithering. It produces animated GIFs that use thousands of colors per frame and up to 50 FPS (useful for showing off design work on Dribbble).

You can also produce smaller lower quality GIFs when needed with the “Quality” slider, thanks to [`gifsicle`](https://github.com/kohler/gifsicle).

Gifski supports all the video formats that macOS supports (`.mp4` or `.mov` with H264, HEVC, ProRes, etc). The [QuickTime Animation format](https://en.wikipedia.org/wiki/QuickTime_Animation) is not supported. Use [ProRes 4444 XQ](https://en.wikipedia.org/wiki/Apple_ProRes) instead. It's more efficient, more widely supported, and like QuickTime Animation, it also supports alpha channel.

Gifski has a bunch of settings like changing dimensions, speed, frame rate, quality, looping, and more.

## Download

[![](https://sindresorhus.com/assets/download-on-app-store-badge.svg)](https://apps.apple.com/app/id1351639930)

Requires macOS 14 or later.

**Older versions**

- [2.23.0](https://github.com/sindresorhus/Gifski/releases/download/v2.23.0/Gifski.2.23.0.-.macOS.13.zip) for macOS 13+
- [2.22.3](https://github.com/sindresorhus/Gifski/releases/download/v2.22.3/Gifski.2.22.3.-.macOS.12.zip) for macOS 12+
- [2.21.2](https://github.com/sindresorhus/Gifski/releases/download/v2.21.2/Gifski.2.21.2.-.macOS.11.zip) for macOS 11+
- [2.20.2](https://github.com/sindresorhus/Gifski/releases/download/v2.20.2/Gifski.2.20.2.-.macOS.10.15.zip) for macOS 10.15+
- [2.16.0](https://github.com/sindresorhus/Gifski/releases/download/v2.16.0/Gifski.2.16.0.-.macOS.10.14.zip) for macOS 10.14+
- [2.4.0](https://github.com/sindresorhus/Gifski/files/3991913/Gifski.2.4.0.-.High.Sierra.zip) for macOS 10.13+

**Non-App Store version**

A special version for users that cannot access the App Store. It won't receive automatic updates. I will update it here once a year.

[Download](https://github.com/sindresorhus/meta/files/13539147/Gifski-2.23.0-1692807940.zip) *(2.23.0 · macOS 13+)*

## Features

### Share extension

Gifski includes a share extension that lets you share videos to Gifski. Just select Gifski from the Share menu of any macOS app.

> Tip: You can share a macOS screen recording with Gifski by clicking on the thumbnail that pops up once you are done recording and selecting “Share” from there.

### System service

Gifski includes a [system service](https://www.computerworld.com/article/2476298/os-x-a-quick-guide-to-services-on-your-mac.html) that lets you quickly convert a video to GIF from the **Services** menu in any app that provides a compatible video file.

### Bounce (yo-yo) GIF playback

Gifski includes the option to create GIFs that bounce back and forth between forward and backward playback. This is a similar effect to the bounce effect in [iOS's Live Photo effects](https://support.apple.com/en-us/HT207310). This option doubles the number of frames in the GIF so the file size will double as well.

<!-- ### Batch conversion

You can use the Shortcuts app to do batch conversions or any kind of automated GIF generation. Look for the “Convert Video to Animated GIF” action in the Shortcuts app. -->

## Tips

#### Quickly copy or save the GIF

After converting, press <kbd>Command+C</kbd> to copy the GIF or <kbd>Command+S</kbd> to save it.

#### Change GIF dimensions with the keyboard

<img src="https://user-images.githubusercontent.com/170270/59964494-b8519f00-952b-11e9-8d16-47c8bc103a61.gif" width="226" height="80" align="right">

In the width/height input fields in the editor view, press the arrow up/down keys to change the value by 1. Hold the Option key meanwhile to change it by 10.

## Screenshots

<img src="Stuff/screenshot1.jpg" width="720" height="450">
<img src="Stuff/screenshot2.jpg" width="720" height="450">
<img src="Stuff/screenshot3.jpg" width="720" height="450">
<img src="Stuff/screenshot4.jpg" width="720" height="450">

## Building from source

To build the app in Xcode, you need to have [Rust](https://www.rust-lang.org) installed first:

```sh
curl https://sh.rustup.rs -sSf | sh
brew install SwiftLint
xcode-select --install
```

## Tips

## Quick Action shortcut

Convert videos to GIFs directly from Finder using the built-in [Quick Action](https://support.apple.com/en-mz/guide/mac-help/mchl97ff9142/mac) shortcut. It works without opening Gifski, and you can create multiple shortcuts with different settings, such as quality, dimensions, or looping, to match your workflow.

[Download shortcut](https://www.icloud.com/shortcuts/8a00497b180742139474d5470857d699)

**Requires the [TestFlight version](https://testflight.apple.com/join/iCyHNNIA) of Gifski**

## FAQ

#### The generated GIFs are huge!

The GIF image format is very space inefficient. It works best with short video clips. Try reducing the dimensions, FPS, or quality.

#### Why are 60 FPS and higher not supported?

Browsers throttle frame rates above 50 FPS, playing them at 10 FPS. [Read more](https://github.com/sindresorhus/Gifski/issues/161#issuecomment-552547771).

#### How can I convert a sequence of PNG images to a GIF?

Install [FFmpeg](https://www.ffmpeg.org/) (with Homebrew: `brew install ffmpeg`) and then run this command:

```
TMPFILE="$(mktemp /tmp/XXXXXXXXXXX).mov"; \
	ffmpeg -f image2 -framerate 30 -i image_%06d.png -c:v prores_ks -profile:v 5 "$TMPFILE" \
	&& open -a Gifski "$TMPFILE"
```

Ensure the images are named in the format `image_000001.png` and adjust the `-framerate` accordingly.

[*Command explanation.*](https://avpres.net/FFmpeg/sq_ProRes.html)

#### How can I run multiple conversions at the same time?

This is unfortunately not supported in the app itself, but you can do it from the Shortcuts app using the shortcut action that comes with the app.

If you know how to run a terminal command, you could also run `open -na Gifski` multiple times to open multiple instances of Gifski, where each instance can convert a separate video. You should not have the editor view open in multiple instances though, as changing the quality, for example, will change it in all the instances.

#### Is it possible to convert from WebM?

Gifski supports the video formats macOS supports, which does not include WebM.

You can convert your video to MP4 first with [this app](https://apps.apple.com/app/id1518836004).

#### Can I contribute localizations?

We don't plan to localize the app.

#### Can you support Windows and Linux?

No, but there's a [cross-platform command-line tool](https://github.com/ImageOptim/gifski) available.

#### [More FAQs…](https://sindresorhus.com/apps/faq)

## Press

- [Five Mac Apps Worth Checking Out - September 2019 - MacRumors](https://www.macrumors.com/2019/09/04/five-mac-apps-sept-2019/)

## Built with

- [gifski library](https://github.com/ImageOptim/gifski) - High-quality GIF encoder
- [Defaults](https://github.com/sindresorhus/Defaults) - Swifty and modern UserDefaults
- [DockProgress](https://github.com/sindresorhus/DockProgress) - Show progress in your app's Dock icon

## Maintainers

- [Sindre Sorhus](https://github.com/sindresorhus)
- [Kornel Lesiński](https://github.com/kornelski)

## Related

- [Sindre's apps](https://sindresorhus.com/apps)

## License

MIT (the Mac app) + [gifski library license](https://github.com/ImageOptim/gifski/blob/master/LICENSE)
