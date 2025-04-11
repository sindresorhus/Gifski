import SwiftUI
import CoreTransferable
import AVFoundation
import Defaults

enum Constants {
	static let allowedFrameRate = 3.0...50.0
	static let loopCountRange = 0...100
}



extension CGRect: Defaults.Serializable {
	static let initialCropRect: CGRect = .init(x: 0, y: 0, width: 1, height: 1)
}

struct CropRect {
	var origin: UnitPoint
	var size: UnitPoint

	var width: Double {
		get {
			size.x
		}
		set {
			size.x = newValue
		}
	}
	var height: Double {
		get {
			size.y
		}
		set {
			size.y = newValue
		}
	}
	var x: Double {
		get {
			origin.x
		}
		set {
			origin.x = newValue
		}
	}
	var y: Double {
		get {
			origin.y
		}
		set {
			origin.y = newValue
		}
	}
	var midX: Double {
		origin.x + (size.x / 2)
	}
	var midY: Double {
		origin.y + (size.y / 2)
	}

	init(origin: UnitPoint, size: UnitPoint) {
		self.origin = origin
		self.size = size
	}
	init(x: Double, y: Double, width: Double, height: Double) {
		self.origin = .init(x: x, y: y)
		self.size = .init(x: width, y: height)
	}
	static let initialCropRect: CropRect = .init(x: 0, y: 0, width: 1, height: 1)
	var isReset: Bool {
		origin.x == 0 && origin.y == 0 && size.x == 1 && size.y == 1
	}
}

extension Defaults.Keys {
	static let outputQuality = Key<Double>("outputQuality", default: 1)
	static let outputSpeed = Key<Double>("outputSpeed", default: 1)
	static let outputFPS = Key<Int>("outputFPS", default: 10)
	static let loopGIF = Key<Bool>("loopGif", default: true)
	static let bounceGIF = Key<Bool>("bounceGif", default: false)
	static let suppressKeyframeWarning = Key<Bool>("suppressKeyframeWarning", default: false)
	static let suppressCropTooltip = Key<Bool>("suppressCropTooltip", default: false)
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
