import Cocoa
import Defaults

struct Constants {
	static let defaultWindowSize = CGSize(width: 360, height: 240)
	static let backgroundImage = NSImage(named: "BackgroundImage")!
	static let allowedFrameRate = 5.0...60.0
}

extension NSColor {
	static let themeColor = NSColor.controlAccentColorPolyfill
	static let progressCircleColor = NSColor(named: "ProgressCircleColor")!

	enum Checkerboard {
		static let first = NSColor(named: "CheckerboardFirstColor")!
		static let second = NSColor(named: "CheckerboardSecondColor")!
	}
}

extension Defaults.Keys {
	static let outputQuality = Key<Double>("outputQuality", default: 1)
	static let loopGif = Key<Bool>("loopGif", default: true)
}
