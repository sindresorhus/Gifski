import Foundation
import AVFoundation

/**
Creates an `AVMutableComposition` with a video track and an `AVVideoComposition` that uses `PreviewVideoCompositor`.
*/
final class PreviewableComposition: AVMutableComposition {
	enum Error: Swift.Error {
		case assetHasNoVideoTrack
		case couldNotCreateVideoTrack
	}

	private(set) var videoComposition: AVVideoComposition!

	init(asset: AVAsset) async throws {
		super.init()

		guard let sourceVideoTrack = try await asset.firstVideoTrack else {
			throw Error.assetHasNoVideoTrack
		}

		let (naturalSize, preferredTransform, timeRange) = try await sourceVideoTrack.load(.naturalSize, .preferredTransform, .timeRange)
		let frameDuration = try await sourceVideoTrack.videoCompositionFrameDuration

		guard
			let compositionVideoTrack = addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
		else {
			throw Error.couldNotCreateVideoTrack
		}
		compositionVideoTrack.preferredTransform = preferredTransform

		// Insert the source track range at zero so preview playback, trimming, and full-preview indexing all use the same normalized timeline.
		try compositionVideoTrack.insertTimeRange(
			timeRange,
			of: sourceVideoTrack,
			at: .videoZero
		)

		// Render size in preferred space (rotated) so preview displays correctly.
		let rotatedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
		let renderSize = CGSize(width: abs(rotatedRect.width), height: abs(rotatedRect.height))
		let instructionTimeRange = CMTimeRange(start: .videoZero, duration: timeRange.duration)

		let layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: compositionVideoTrack)
		let instructionConfig = AVVideoCompositionInstruction.Configuration(
			layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layerConfig)],
			timeRange: instructionTimeRange
		)
		// The GIF preview can change between source frames, so it needs fixed-cadence redraws rather than source frame timing.
		let configuration = AVVideoComposition.Configuration(
			customVideoCompositorClass: PreviewVideoCompositor.self,
			frameDuration: frameDuration,
			instructions: [AVVideoCompositionInstruction(configuration: instructionConfig)],
			renderSize: renderSize
		)
		videoComposition = AVVideoComposition(configuration: configuration)
	}
}
