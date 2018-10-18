<div align="center">
	<img src="Stuff/AppIcon-readme.png" width="256" height="256">
	<h1>Gifski</h1>
	<p>
		<b>Convert videos to high-quality GIFs on your Mac</b>
	</p>
	<br>
	<br>
	<br>
</div>

This is a macOS app for the [`gifski` encoder](https://gif.ski), which converts videos to GIF animations using [`pngquant`](https://pngquant.org)'s fancy features for efficient cross-frame palettes and temporal dithering. It produces animated GIFs that use thousands of colors per frame.

**[Blog post](https://blog.sindresorhus.com/gifski-972692460aa5)** &nbsp;&nbsp; **[Product Hunt](https://www.producthunt.com/posts/gifski)**

Requires macOS 10.13 or later.


## Download

[![](https://linkmaker.itunes.apple.com/assets/shared/badges/en-us/macappstore-lrg.svg)](https://itunes.apple.com/no/app/gifski/id1351639930?mt=12)


## Screenshots

<img src="Stuff/screenshot.jpg" width="918" height="413">
<img src="Stuff/screenshot2.jpg" width="918" height="413">


## Building from source

To build the app in Xcode, you need to have [Rust](https://www.rust-lang.org) and GCC 8 installed first:

```sh
curl https://sh.rustup.rs -sSf | sh
brew install gcc@8 SwiftLint
xcode-select --install
```


## Built with

- [gifski library](https://github.com/ImageOptim/gifski) - High-quality GIF encoder
- [Defaults](https://github.com/sindresorhus/Defaults/blob/master/readme.md) - Swifty and modern UserDefaults
- [CircularProgress](https://github.com/sindresorhus/CircularProgress) - Circular progress indicator your macOS app
- [DockProgress](https://github.com/sindresorhus/DockProgress) - Show progress in your app's Dock icon


## Links

- [More Swift packages by me](https://github.com/search?q=user%3Asindresorhus+language%3Aswift)


## Maintainers

- [Sindre Sorhus](https://github.com/sindresorhus)
- [Kornel Lesiński](https://github.com/kornelski)
- [Lars-Jørgen Kristiansen](https://github.com/LarsJK)


## License

MIT (the Mac app) + [gifski library license](https://github.com/ImageOptim/gifski/blob/master/LICENSE)
