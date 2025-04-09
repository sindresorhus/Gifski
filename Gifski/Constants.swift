import SwiftUI
import CoreTransferable
import AVFoundation

enum Constants {
	static let allowedFrameRate = 3.0...50.0
	static let loopCountRange = 0...100
}


extension UserDefaults {
	static let sharedGroup = UserDefaults(
		suiteName: Shared.videoShareGroupIdentifier
	) ?? UserDefaults.standard
}

extension Defaults.Keys {
	static let outputQuality = Key<Double>("outputQuality", default: 1)
	static let outputSpeed = Key<Double>("outputSpeed", default: 1)
	static let outputFPS = Key<Int>("outputFPS", default: 10)
	static let loopGIF = Key<Bool>("loopGif", default: true)
	static let bounceGIF = Key<Bool>("bounceGif", default: false)
	static let suppressKeyframeWarning = Key<Bool>("suppressKeyframeWarning", default: false)

	static let quickOutputQuality = Key<Double>("quickOutputQuality", default: 0.5, suite: .sharedGroup)
	static let quickOutputSpeed = Key<Double>("quickOutputSpeed", default: 1, suite: .sharedGroup)
	static let quickOutputFPS = Key<Int>("quickOutputFPS", default: 10, suite: .sharedGroup)
	static let quickLoopGIF = Key<Bool>("quickLoopGif", default: true, suite: .sharedGroup)
	static let quickLoopCount = Key<Int>("quickLoopCount", default: 0, suite: .sharedGroup)
	static let quickBounceGIF = Key<Bool>("quickBounceGif", default: false, suite: .sharedGroup)
	static let quickResize = Key<Double>("quickResize", default: 1.0, suite: .sharedGroup)
}

enum Route: Hashable {
	case edit(URL, AVAsset, AVAsset.VideoMetadata)
	case conversion(GIFGenerator.Conversion)
	case completed(Data, URL)
}

struct ExportableGIF: Transferable {
	let url: URL

	static var transferRepresentation: some TransferRepresentation {
		FileRepresentation(exportedContentType: .gif) { .init($0.url) }
			// TODO: Does not work when using `.fileExporter`. (macOS 14.3)
			.suggestedFileName { $0.url.filename }
	}
}
