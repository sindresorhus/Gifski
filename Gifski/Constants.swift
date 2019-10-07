import Cocoa

extension NSColor {
	static let themeColor = NSColor.controlAccentColorPolyfill

	enum Checkerboard {
		static let first = NSColor(named: "CheckerboardFirstColor")!
		static let second = NSColor(named: "CheckerboardSecondColor")!
	}
}

extension Defaults.Keys {
	static let outputQuality = Key<Double>("outputQuality", default: 1)
	static let successfulConversionsCount = Key<Int>("successfulConversionsCount", default: 0)
}

struct Constants {
	static let defaultWindowSize = CGSize(width: 360, height: 240)
	static let backgroundImage = NSImage(named: "BackgroundImage")!
}
