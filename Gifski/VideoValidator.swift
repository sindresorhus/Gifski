import AVKit
import FirebaseCrashlytics

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
		Crashlytics.record(
			key: "File size",
			value: inputUrl.fileSize
		)

		guard inputUrl.fileSize > 0 else {
			NSAlert.showModal(
				for: window,
				title: "The selected file is empty.",
				message: "Try selecting a different file."
			)

			return .failure
		}

		// TODO: Use `UTType#conforms(to:)` when targeting macOS 11.
		// This is very unlikely to happen. We have a lot of file type filters in place, so the only way this can happen is if the user right-clicks a non-video in Finder, chooses "Open With", then "Other…", chooses "All Applications", and then selects Gifski. Yet, some people are doing this…
		guard inputUrl.conformsTo(typeIdentifier: kUTTypeMovie as String) else {
			NSAlert.showModal(
				for: window,
				title: "The selected file could not be converted because it's not a video.",
				message: "Try again with a video file, usually with the file extension “mp4” or “mov”."
			)

			return .failure
		}

		let asset = AVURLAsset(
			url: inputUrl,
			options: [
				AVURLAssetPreferPreciseDurationAndTimingKey: true
			]
		)

		Crashlytics.record(key: "AVAsset debug info", value: asset.debugInfo)

		guard asset.videoCodec != .appleAnimation else {
			NSAlert.showModal(
				for: window,
				title: "The QuickTime Animation format is not supported.",
				message: "Re-export or convert the video to ProRes 4444 XQ instead. It's more efficient, more widely supported, and like QuickTime Animation, it also supports alpha channel. To convert an existing video, open it in QuickTime Player, which will automatically convert it, and then save it."
			)

			return .failure
		}

		if asset.hasAudio, !asset.hasVideo {
			NSAlert.showModal(
				for: window,
				title: "Audio files are not supported.",
				message: "Gifski converts video files but the provided file is audio-only. Please provide a file that contains video."
			)

			return .failure
		}

		guard let firstVideoTrack = asset.firstVideoTrack else {
			NSAlert.showModal(
				for: window,
				title: "Could not read any video from the video file.",
				message: "Either the video format is unsupported by macOS or the file is corrupt."
			)

			return .failure
		}

		guard !asset.hasProtectedContent else {
			NSAlert.showModal(
				for: window,
				title: "The video is DRM-protected and cannot be converted."
			)

			return .failure
		}

		// We already specify the UTIs we support, so this can only happen on invalid video files or unsupported codecs.
		guard asset.isVideoDecodable else {
			if
				let codec = firstVideoTrack.codec,
				codec.isSupported
			{
				NSAlert.showModalAndReportToCrashlytics(
					for: window,
					title: "The video could not be decoded even though its codec “\(codec)” is supported.",
					message: "This could happen if the video is corrupt or the codec profile level is not supported. macOS unfortunately doesn't provide Gifski a reason for why the video could not be decoded. Try re-exporting using a different configuration or try converting the video to HEVC (MP4) with the free HandBrake app.",
					showDebugInfo: false,
					debugInfo: asset.debugInfo
				)

				return .failure
			}

			guard let codecTitle = firstVideoTrack.codecTitle else {
				NSAlert.showModalAndReportToCrashlytics(
					for: window,
					title: "The video file is not supported.",
					message: "I'm trying to figure out why this happens. It would be amazing if you could email the below details to sindresorhus@gmail.com",
					debugInfo: asset.debugInfo
				)

				return .failure
			}

			guard codecTitle != "hev1" else {
				NSAlert.showModal(
					for: window,
					title: "This variant of the HEVC video codec is not supported by macOS.",
					message: "The video uses the “hev1” variant of HEVC while macOS only supports “hvc1”. Try re-exporting the video using a different configuration or use the free HandBrake app to convert the video to the supported HEVC variant."
				)

				return .failure
			}

			NSAlert.showModalAndReportToCrashlytics(
				for: window,
				title: "The video codec “\(codecTitle)” is not supported.",
				message: "Re-export or convert the video to a supported format. For the best possible quality, export to ProRes 4444 XQ (supports alpha). Alternatively, use the free HandBrake app to convert the video to HEVC (MP4).",
				showDebugInfo: false,
				debugInfo: asset.debugInfo
			)

			return .failure
		}

		guard asset.videoMetadata != nil else {
			NSAlert.showModalAndReportToCrashlytics(
				for: window,
				title: "The video metadata is not readable.",
				message: "Please open an issue on https://github.com/sindresorhus/Gifski or email sindresorhus@gmail.com. ZIP the video and attach it.\n\nInclude this info:",
				debugInfo: asset.debugInfo
			)

			return .failure
		}

		guard
			let dimensions = asset.dimensions,
			dimensions.width >= 4,
			dimensions.height >= 4
		else {
			NSAlert.showModal(
				for: window,
				title: "The video dimensions must be at least 4×4.",
				message: "The dimensions of the video are \(asset.dimensions?.formatted ?? "0×0")."
			)

			return .failure
		}

		// We extract the video track into a new asset to remove the audio and to prevent problems if the video track duration is shorter than the total asset duration. If we don't do this, the video will show as black in the trim view at the duration where there's no video track, and it will confuse users. Also, if the user trims the video to just the black no video track part, the conversion would continue, but there's nothing to convert, so it would be stuck at 0%.
		guard
			let newAsset = firstVideoTrack.extractToNewAsset(),
			let newVideoMetadata = newAsset.videoMetadata
		else {
			NSAlert.showModalAndReportToCrashlytics(
				for: window,
				title: "Could not read the video.",
				message: "This should not happen. Email sindresorhus@gmail.com and include this info:",
				debugInfo: asset.debugInfo
			)

			return .failure
		}

		// Trim asset
		do {
			let trimmedAsset = try newAsset.trimmingBlankFramesFromFirstVideoTrack()
			return .success(trimmedAsset, newVideoMetadata)
		} catch {
			NSAlert.showModalAndReportToCrashlytics(
				for: window,
				title: "Could not trim empty leading frames from video.",
				message: "\(error.localizedDescription)\n\nThis should not happen. Email sindresorhus@gmail.com and include this info:",
				debugInfo: newAsset.debugInfo
			)

			return .failure
		}
	}
}
