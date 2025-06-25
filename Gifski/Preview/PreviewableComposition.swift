import Foundation
import AVFoundation

/**
Adds `PreviewVideoCompositor` to a `AVComposition`, setting up the instructions and tracks.
*/
final class PreviewableComposition: AVMutableComposition {
	enum Error: Swift.Error {
		case assetHasNoTracks
		case couldNotCreateTracks
	}

	let videoComposition = AVMutableVideoComposition()

	init(extractPreviewableCompositionFrom asset: AVAsset) async throws {
		super.init()

		let (assetTracks, duration) = try await asset.load(.tracks, .duration)

		guard let assetTrack = assetTracks.first else {
			throw Error.assetHasNoTracks
		}

		let (trackSize, frameDuration) = try await assetTrack.load(.naturalSize, .minFrameDuration)

		guard
			let compositionOriginalTrack = addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
		else {
			throw Error.couldNotCreateTracks
		}

		try compositionOriginalTrack.insertTimeRange(
			CMTimeRange(start: .videoZero, duration: duration),
			of: assetTrack,
			at: .videoZero
		)

		let instruction = AVMutableVideoCompositionInstruction()
		instruction.timeRange = CMTimeRange(start: .videoZero, duration: duration)
		instruction.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: compositionOriginalTrack)]

		videoComposition.frameDuration = frameDuration
		videoComposition.renderSize = trackSize
		videoComposition.instructions = [instruction]
		videoComposition.customVideoCompositorClass = PreviewVideoCompositor.self
	}
}
