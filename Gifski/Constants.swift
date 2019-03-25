import Cocoa

extension NSColor {
	static let appTheme = NSColor.controlAccentColorPolyfill
}

extension Defaults.Keys {
	static let outputQuality = Defaults.Key<Double>("outputQuality", default: 1)
}
