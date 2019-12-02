import Crashlytics
import AVKit

struct VideoValidator {
	enum Result {
		case failure
		case success(AVAsset, AVAsset.VideoMetadata)
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
		guard
			asset.isVideoDecodable,
			let firstVideoTrack = asset.firstVideoTrack
		else {
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
			NSAlert.showModal(
				for: window,
				message: "The video dimensions must be at least 10×10.",
				informativeText: "The dimensions of your video are \(asset.dimensions?.formatted ?? "0×0")."
			)

			return .failure
		}

		// If the video track duration is shorter than the total asset duration, we extract the video track into a new asset to prevent problems later on. If we don't do this, the video will show as black in the trim view at the duration where there's no video track, and it will confuse users. Also, if the user trims the video to just the black no video track part, the conversion would continue, but there's nothing to convert, so it would be stuck at 0%.
		guard firstVideoTrack.isFullDuration else {
			guard
				let newAsset = firstVideoTrack.extractToNewAsset(),
				let newVideoMetadata = newAsset.videoMetadata
			else {
				NSAlert.showModalAndReportToCrashlytics(
					for: window,
					message: "Cannot read the video.",
					informativeText: "Please open an issue on https://github.com/sindresorhus/Gifski or email sindresorhus@gmail.com. ZIP the video and attach it.\n\nInclude this info:",
					debugInfo: asset.debugInfo
				)

				return .failure
			}

			return .success(newAsset, newVideoMetadata)
		}

		return .success(asset, videoMetadata)
	}
}
