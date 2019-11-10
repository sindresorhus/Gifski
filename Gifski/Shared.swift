import Foundation

struct Shared {
	static let appIdentifierPrefix = Bundle.main.infoDictionary!["AppIdentifierPrefix"] as! String
	static let videoShareGroupIdentifier = "\(appIdentifierPrefix)gifski_video_share_group"
}
