import Cocoa

enum Constants {
	static let defaultWindowSize = CGSize(width: 360, height: 240)
	static let allowedFrameRate = 3.0...50.0
	static let loopCountRange = 0...100
}

extension Defaults.Keys {
	static let outputQuality = Key<Double>("outputQuality", default: 1)
	static let outputSpeed = Key<Double>("outputSpeed", default: 1)
	static let outputFPS = Key<Int>("outputFPS", default: 10)
	static let loopGif = Key<Bool>("loopGif", default: true)
	static let bounceGif = Key<Bool>("bounceGif", default: false)
	static let suppressKeyframeWarning = Key<Bool>("suppressKeyframeWarning", default: false)
	static let previousSaveDirectory = Key<URL?>("previousSaveDirectory")
}
