import Cocoa

extension NSColor {
	static let themeColor = NSColor.controlAccentColorPolyfill
}

extension Defaults.Keys {
	static let outputQuality = Key<Double>("outputQuality", default: 1)
	static let successfulConversionsCount = Key<Int>("successfulConversionsCount", default: 0)
}
