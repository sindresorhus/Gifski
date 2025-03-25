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
/// Codable Rect for Cropping
/// The coordinates are as follows:
/// - The origin in the upper left hand corner
///  - x is in [0,1]
///  - y is in [0,1]
///  It's just like a texCoords in a UV texture
///  in common graphics subroutines.
typealias CropRect = CGRect

extension Defaults.Keys {
	static let outputQuality = Key<Double>("outputQuality", default: 1)
	static let outputSpeed = Key<Double>("outputSpeed", default: 1)
	static let outputFPS = Key<Int>("outputFPS", default: 10)
	static let loopGIF = Key<Bool>("loopGif", default: true)
	static let bounceGIF = Key<Bool>("bounceGif", default: false)
	static let outputCrop = Key<Bool>("outputCrop", default: false)
	static let outputCropRect: Key<CropRect> = .init("outputCropRect", default: .initialCropRect)
	static let suppressKeyframeWarning = Key<Bool>("suppressKeyframeWarning", default: false)
}

enum Route: Hashable {
	case edit(URL, AVAsset, AVAsset.VideoMetadata)
	case conversion(GIFGenerator.Conversion)
	case completed(Data, URL)
	case editCrop(AVAsset, AVAsset.VideoMetadata, /* BounceGIF */ Bool)
}

struct ExportableGIF: Transferable {
	let url: URL

	static var transferRepresentation: some TransferRepresentation {
		FileRepresentation(exportedContentType: .gif) { .init($0.url) }
			// TODO: Does not work when using `.fileExporter`. (macOS 14.3)
			.suggestedFileName { $0.url.filename }
	}
}
