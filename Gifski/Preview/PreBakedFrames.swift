import Foundation
import AVKit

/**
 Bug in AVPlayer: if the left trimmer is to the far left (the beginning of the video) or the far right, the avVideoPlayer will prevent frame redraws on swiftUI updates (like pressing the showPreviewButton on / off). I have tried everything I can think of to find the real source of the error, but for now here is a workaround. We offset the track by just a bit on each end and prebake the frames just for the end. This offset will prevent the fullPreviewTrack from spanning the entire video range, and the pre-render keeps smooth video playback.
 */
struct PreBakedFrames {
	private let frames: [Int: CGImage]
	private let frameRate: Double

	private let offsets: Offsets
	private let timeRange: ClosedRange<Double>
	private let numberOfFrames: Int

	private static let bugFixOffset = 0.1

	init(_ imageSource: CGImageSource, settings: SettingsForFullPreview) async throws {
		numberOfFrames = CGImageSourceGetCount(imageSource)
		guard numberOfFrames > 0 else {
			throw CreateAVAssetError.noImages
		}
		frameRate = Double(settings.conversion.frameRate ?? 30)
		offsets = Offsets(settings: settings)
		timeRange = settings.conversion.timeRange ?? 0...settings.assetDuration
		let speed = settings.speed

		// +1 just to be safe
		let numberOfFramesToPrecomputeAtTheBeginning = min(
			numberOfFrames,
			Int(ceil(offsets.start.seconds * frameRate * speed)) + 1
		)
		let numberOfFramesToPrecomputeAtTheEnd = min(
			numberOfFrames,
			Int(ceil(offsets.end.seconds * frameRate * speed)) + 1
		)

		let beginningRange = Set(0..<numberOfFramesToPrecomputeAtTheBeginning)
		let endRange = Set(numberOfFrames - numberOfFramesToPrecomputeAtTheEnd..<numberOfFrames)
		let allFrames = beginningRange.union(endRange)

		let dict = try await allFrames.asyncMap { frameIndex in
			guard let image = CGImageSourceCreateImageAtIndex(imageSource, frameIndex, nil) else {
				throw CreateAVAssetError.failedToCreateImage
			}
			return (frameIndex, image)
		}
		self.frames = Dictionary(uniqueKeysWithValues: dict)
	}

	func getPreBakedFrame(forTime time: PreviewVideoCompositor.OriginalCompositionTime) -> CGImage? {
		let fullPreviewTime = time.seconds - timeRange.lowerBound
		let frameIndex = Int(floor(fullPreviewTime * frameRate)).clamped(to: 0..<numberOfFrames)
		return frames[frameIndex]
	}

	struct Offsets: Equatable {
		let start: CMTime
		let end: CMTime

		init(settings: SettingsForFullPreview) {
			let fullPreviewRange = settings.conversion.timeRange ?? 0...settings.assetDuration

			self.init(
				fullPreviewStartTime: CMTime(seconds: fullPreviewRange.lowerBound, preferredTimescale: .video),
				fullPreviewEndTime: CMTime(seconds: fullPreviewRange.upperBound, preferredTimescale: .video),
				originalTrackTimeRange: CMTimeRange(
					start: .zero,
					duration: .init(seconds: settings.assetDuration, preferredTimescale: .video)
				)
			)
		}

		init(
			fullPreviewStartTime: CMTime,
			fullPreviewEndTime: CMTime,
			originalTrackTimeRange: CMTimeRange
		) {
			start = fullPreviewStartTime <= originalTrackTimeRange.start
			? CMTime(seconds: PreBakedFrames.bugFixOffset, preferredTimescale: .video)
			: .zero
			end = fullPreviewEndTime >= originalTrackTimeRange.end
			? CMTime(seconds: PreBakedFrames.bugFixOffset, preferredTimescale: .video)
			: .zero
		}
	}
}
