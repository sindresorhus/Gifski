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

This is a macOS app for the [`gifski` encoder](https://gif.ski), which converts videos to GIF animations using [`pngquant`](https://pngquant.org)'s fancy features for efficient cross-frame palettes and temporal dithering. It produces animated GIFs that use thousands of colors per frame.

You can also produce smaller lower quality GIFs when needed with the “Quality” slider, thanks to [`gifsicle`](https://github.com/kohler/gifsicle).

Gifski supports all the video formats that macOS supports (`.mp4` or `.mov` with H264, HEVC, ProRes, etc). The [QuickTime Animation format](https://en.wikipedia.org/wiki/QuickTime_Animation) is not supported. Use [ProRes 4444 XQ](https://en.wikipedia.org/wiki/Apple_ProRes) instead. It's more efficient, more widely supported, and like QuickTime Animation, it also supports alpha channel.

**[Blog post](https://blog.sindresorhus.com/gifski-972692460aa5)** &nbsp;&nbsp; **[Product Hunt](https://www.producthunt.com/posts/gifski-2)**

Requires macOS 10.14 or later.

## Download

[![](https://linkmaker.itunes.apple.com/assets/shared/badges/en-us/macappstore-lrg.svg)](https://apps.apple.com/us/app/gifski/id1351639930?mt=12)

## Features

### Share extension

Gifski includes a share extension that lets you share videos to Gifski. Just select Gifski from the Share menu of any macOS app.

> Tip: You can share a macOS screen recording with Gifski by clicking on the thumbnail that pops up once you are done recording and selecting “Share” from there.

### System service

Gifski includes a [system service](https://www.computerworld.com/article/2476298/os-x-a-quick-guide-to-services-on-your-mac.html) that lets you quickly convert a video to GIF from the **Services** menu in any app that provides a compatible video file.

### Change GIF dimensions with the keyboard

<img src="https://user-images.githubusercontent.com/170270/59964494-b8519f00-952b-11e9-8d16-47c8bc103a61.gif" width="226" height="80" align="right">

In the width/height input fields in the editor view, press the arrow up/down keys to change the value by 1. Hold the Option key meanwhile to change it by 10.

## Screenshots

<img src="Stuff/screenshot1.jpg" width="720" height="450">
<img src="Stuff/screenshot2.jpg" width="720" height="450">
<img src="Stuff/screenshot3.jpg" width="720" height="450">
<img src="Stuff/screenshot4.jpg" width="720" height="450">

## Building from source

To build the app in Xcode, you need to have [Rust](https://www.rust-lang.org) and GCC 8 installed first:

```sh
curl https://sh.rustup.rs -sSf | sh
brew install gcc@9 SwiftLint
xcode-select --install
```

## FAQ

### Can I contribute localizations?

No, we're not interested in localizing the app.

### Can you support macOS 10.13?

No, but you can get the last compatible version [here](https://github.com/sindresorhus/Gifski/files/3991913/Gifski.2.4.0.-.High.Sierra.zip).

### Can you support Windows/Linux?

No, but there's a [cross-platform command-line tool](https://github.com/ImageOptim/gifski) available.

## Press

- [Five Mac Apps Worth Checking Out - September 2019 - MacRumors](https://www.macrumors.com/2019/09/04/five-mac-apps-sept-2019/)

## Built with

- [gifski library](https://github.com/ImageOptim/gifski) - High-quality GIF encoder
- [Defaults](https://github.com/sindresorhus/Defaults) - Swifty and modern UserDefaults
- [CircularProgress](https://github.com/sindresorhus/CircularProgress) - Circular progress indicator for your macOS app
- [DockProgress](https://github.com/sindresorhus/DockProgress) - Show progress in your app's Dock icon

## Maintainers

- [Sindre Sorhus](https://github.com/sindresorhus)
- [Kornel Lesiński](https://github.com/kornelski)
- [Lars-Jørgen Kristiansen](https://github.com/LarsJK)
- [Boy van Amstel](https://github.com/boyvanamstel)
- [Łukasz Mróz](https://github.com/sunshinejr)

## Related

- [Plash](https://github.com/sindresorhus/Plash) - Make any website your desktop wallpaper
- [More apps…](https://sindresorhus.com/apps)

## License

MIT (the Mac app) + [gifski library license](https://github.com/ImageOptim/gifski/blob/master/LICENSE)
