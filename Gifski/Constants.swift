import Cocoa
import Defaults

enum Constants {
	static let defaultWindowSize = CGSize(width: 360, height: 240)
	static let backgroundImage = NSImage(named: "BackgroundImage")!
	static let allowedFrameRate = 5.0...50.0
	static let loopCountRange = 0...100
}

extension NSColor {
	static let themeColor = NSColor.controlAccentColor
	static let progressCircleColor = NSColor(named: "ProgressCircleColor")!

	enum Checkerboard {
		static let first = NSColor(named: "CheckerboardFirstColor")!
		static let second = NSColor(named: "CheckerboardSecondColor")!
	}
}

extension Defaults.Keys {
	static let outputQuality = Key<Double>("outputQuality", default: 1)
	static let loopGif = Key<Bool>("loopGif", default: true)
	static let bounceGif = Key<Bool>("bounceGif", default: false)
	static let suppressKeyframeWarning = Key<Bool>("suppressKeyframeWarning", default: false)
}
