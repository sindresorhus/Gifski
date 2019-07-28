import Crashlytics
import AVKit

struct VideoValidator {
	enum Result {
		case failure
		case success(AVURLAsset, AVURLAsset.VideoMetadata)
	}

	func validate(_ inputUrl: URL, in window: NSWindow?) -> Result {
		Crashlytics.record(
			key: "Does input file exist",
			value: inputUrl.exists
		)
		Crashlytics.record(
			key: "Is input file reachable",
			value: try? inputUrl.checkResourceIsReachable()
		)
		Crashlytics.record(
			key: "Is input file readable",
			value: inputUrl.isReadable
		)

		// This is very unlikely to happen. We have a lot of file type filters in place, so the only way this can happen is if the user right-clicks a non-video in Finder, chooses "Open With", then "Other…", chooses "All Applications", and then selects Gifski. Yet, some people are doing this…
		guard inputUrl.isVideo else {
			NSAlert.showModal(
				for: window,
				message: "The selected file cannot be converted because it's not a video.",
				informativeText: "Try again with a video file, usually with the file extension “mp4” or “mov”."
			)

			return .failure
		}

		let asset = AVURLAsset(url: inputUrl)

		Crashlytics.record(key: "AVAsset debug info", value: asset.debugInfo)

		guard asset.videoCodec != .appleAnimation else {
			NSAlert.showModal(
				for: window,
				message: "The QuickTime Animation format is not supported.",
				informativeText: "Re-export or convert your video to ProRes 4444 XQ instead. It's more efficient, more widely supported, and like QuickTime Animation, it also supports alpha channel. To convert an existing video, open it in QuickTime Player, which will automatically convert it, and then save it."
			)

			return .failure
		}

		if asset.hasAudio && !asset.hasVideo {
			NSAlert.showModal(
				for: window,
				message: "Audio files are not supported.",
				informativeText: "Gifski converts video files but the provided file is audio-only. Please provide a file that contains video."
			)

			return .failure
		}

		// We already specify the UTIs we support, so this can only happen on invalid video files or unsupported codecs.
		guard asset.isVideoDecodable else {
			NSAlert.showModalAndReportToCrashlytics(
				for: window,
				message: "The video file is not supported.",
				informativeText: "Please open an issue on https://github.com/sindresorhus/Gifski or email sindresorhus@gmail.com. ZIP the video and attach it.\n\nInclude this info:",
				debugInfo: asset.debugInfo
			)

			return .failure
		}

		guard let videoMetadata = asset.videoMetadata else {
			NSAlert.showModalAndReportToCrashlytics(
				for: window,
				message: "The video metadata is not readable.",
				informativeText: "Please open an issue on https://github.com/sindresorhus/Gifski or email sindresorhus@gmail.com. ZIP the video and attach it.\n\nInclude this info:",
				debugInfo: asset.debugInfo
			)

			return .failure
		}

		guard
			let dimensions = asset.dimensions,
			dimensions.width > 10,
			dimensions.height > 10
		else {
			NSAlert.showModalAndReportToCrashlytics(
				for: window,
				message: "The video dimensions must be at least 10×10.",
				informativeText: "The dimensions of your video are \(asset.dimensions?.formatted ?? "0×0").\n\nIf you think this error is a mistake, please open an issue on https://github.com/sindresorhus/Gifski or email sindresorhus@gmail.com. ZIP the video and attach it.\n\nInclude this info:",
				debugInfo: asset.debugInfo
			)

			return .failure
		}

		return .success(asset, videoMetadata)
	}
}
