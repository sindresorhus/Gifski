import AVFoundation

enum VideoValidator {
	static func validate(_ inputUrl: URL) async throws -> (asset: AVAsset, metadata: AVAsset.VideoMetadata) {
//		Crashlytics.record(
//			key: "Does input file exist",
//			value: inputUrl.exists
//		)
//		Crashlytics.record(
//			key: "Is input file reachable",
//			value: try? inputUrl.checkResourceIsReachable()
//		)
//		Crashlytics.record(
//			key: "Is input file readable",
//			value: inputUrl.isReadable
//		)
//		Crashlytics.record(
//			key: "File size",
//			value: inputUrl.fileSize
//		)

		guard inputUrl.fileSize > 0 else {
			throw NSError.appError(
				"The selected file is empty.",
				recoverySuggestion: "Try selecting a different file."
			)
		}

		// This is very unlikely to happen. We have a lot of file type filters in place, so the only way this can happen is if the user right-clicks a non-video in Finder, chooses "Open With", then "Other…", chooses "All Applications", and then selects Gifski. Yet, some people are doing this…
		guard inputUrl.contentType?.conforms(to: .movie) == true else {
			throw NSError.appError(
				"The selected file could not be converted because it's not a video.",
				recoverySuggestion: "Try again with a video file, usually with the file extension “mp4”, “m4v”, or “mov”."
			)
		}

		let asset = AVURLAsset(
			url: inputUrl,
			options: [
				AVURLAssetPreferPreciseDurationAndTimingKey: true
			]
		)

		let (hasProtectedContent) = try await asset.load(.hasProtectedContent)

//		Crashlytics.record(key: "AVAsset debug info", value: asset.debugInfo)

		guard try await asset.videoCodec != .appleAnimation else {
			throw NSError.appError(
				"The QuickTime Animation format is not supported.",
				recoverySuggestion: "Re-export or convert the video to ProRes 4444 XQ instead. It's more efficient, more widely supported, and like QuickTime Animation, it also supports alpha channel. To convert an existing video, open it in QuickTime Player, which will automatically convert it, and then save it."
			)
		}

		// TODO: Parallelize these checks.
		if
			try await asset.hasAudio,
			try await !asset.hasVideo
		{
			throw NSError.appError(
				"Audio files are not supported.",
				recoverySuggestion: "Gifski converts video files but the provided file is audio-only. Please provide a file that contains video."
			)
		}

		guard let firstVideoTrack = try await asset.firstVideoTrack else {
			throw NSError.appError(
				"Could not read any video from the video file.",
				recoverySuggestion: "Either the video format is unsupported by macOS or the file is corrupt."
			)
		}

		guard !hasProtectedContent else {
			throw NSError.appError("The video is DRM-protected and cannot be converted.")
		}

		let cannotReadVideoExplanation = "This could happen if the video is corrupt or the codec profile level is not supported. macOS unfortunately doesn't provide Gifski a reason for why the video could not be decoded. Try re-exporting using a different configuration or try converting the video to HEVC (MP4) with the free HandBrake app."

		let codecTitle = try await firstVideoTrack.codecTitle

		// We already specify the UTIs we support, so this can only happen on invalid video files or unsupported codecs.
		guard try await asset.isVideoDecodable else {
			if
				let codec = try await firstVideoTrack.codec,
				codec.isSupported
			{
				throw NSError.appError(
					"The video could not be decoded even though its codec “\(codec)” is supported.",
					recoverySuggestion: cannotReadVideoExplanation
				)
			}

			guard let codecTitle else {
				throw NSError.appError(
					"The video file is not supported.",
					recoverySuggestion: "I'm trying to figure out why this happens. It would be amazing if you could email the below details to sindresorhus@gmail.com\n\n\(try await asset.debugInfo)"
				)
			}

			guard codecTitle != "hev1" else {
				throw NSError.appError(
					"This variant of the HEVC video codec is not supported by macOS.",
					recoverySuggestion: "The video uses the “hev1” variant of HEVC while macOS only supports “hvc1”. Try re-exporting the video using a different configuration or use the free HandBrake app to convert the video to the supported HEVC variant."
				)
			}

			throw NSError.appError(
				"The video codec “\(codecTitle)” is not supported.",
				recoverySuggestion: "Re-export or convert the video to a supported format. For the best possible quality, export to ProRes 4444 XQ (supports alpha). Alternatively, use the free HandBrake app to convert the video to HEVC (MP4)."
			)
		}

		// AVFoundation reports some videos as `.isReadable == true` even though they are not. We detect this through missing codec info. See "Fixture 211". (macOS 13.1)
		guard codecTitle != nil else {
			throw NSError.appError(
				"The video file is not supported.",
				recoverySuggestion: cannotReadVideoExplanation
			)
		}

		guard try await asset.videoMetadata != nil else {
			throw NSError.appError(
				"The video metadata is not readable.",
				recoverySuggestion: "Please open an issue on https://github.com/sindresorhus/Gifski or email sindresorhus@gmail.com. ZIP the video and attach it.\n\nInclude this info:\n\n\(try await asset.debugInfo)"
			)
		}

		guard
			let dimensions = try await asset.dimensions,
			dimensions.width >= 4,
			dimensions.height >= 4
		else {
			throw NSError.appError(
				"The video dimensions must be at least 4×4.",
				recoverySuggestion: "The dimensions of the video are \((try? await asset.dimensions?.formatted) ?? "0×0")."
			)
		}

		// We extract the video track into a new asset to remove the audio and to prevent problems if the video track duration is shorter than the total asset duration. If we don't do this, the video will show as black in the trim view at the duration where there's no video track, and it will confuse users. Also, if the user trims the video to just the black no video track part, the conversion would continue, but there's nothing to convert, so it would be stuck at 0%.
		guard
			let newAsset = try await firstVideoTrack.extractToNewAsset(),
			let newVideoMetadata = try await newAsset.videoMetadata
		else {
			throw NSError.appError(
				"Could not read the video.",
				recoverySuggestion: "This should not happen. Email sindresorhus@gmail.com and include this info:\n\n\(try await asset.debugInfo)"
			)
		}

		// Trim asset
		do {
			let trimmedAsset = try await newAsset.trimmingBlankFramesFromFirstVideoTrack()
			return (trimmedAsset, newVideoMetadata)
		} catch AVAssetTrack.VideoTrimmingError.codecNotSupported {
			// Allow user to continue
			return (newAsset, newVideoMetadata)
		} catch {
			throw NSError.appError(
				"Could not trim empty leading frames from video.",
				recoverySuggestion: "\(error.localizedDescription)\n\nThis should not happen. Email sindresorhus@gmail.com and include this info:\n\n\(try await newAsset.debugInfo)"
			)
		}
	}
}
