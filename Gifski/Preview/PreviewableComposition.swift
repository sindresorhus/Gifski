//
//  AVAsset+Preview.swift
//  Gifski
//
//  Created by Michael Mulet on 4/23/25.
//

import Foundation
import AVFoundation

final class PreviewableComposition: AVMutableComposition {
	let videoComposition = AVMutableVideoComposition()

	init(extractPreviewableCompositionFrom asset: AVAsset) async throws {
		super.init()
		let (assetTracks, duration) = try await asset.load(.tracks, .duration)
		guard let assetTrack = assetTracks.first else {
			throw PreviewableCompositionError.assetHasNoTracks
		}
		let (trackSize, frameDuration) = try await assetTrack.load(.naturalSize, .minFrameDuration)
		guard let compositionOriginalTrack = addMutableTrack(withMediaType: .video, preferredTrackID: .originalVideoTrack),
			  let compositionFullPreviewTrack = addMutableTrack(withMediaType: .video, preferredTrackID: .fullPreviewVideoTrack)
		else {
			throw PreviewableCompositionError.couldNotCreateTracks
		}
		try compositionOriginalTrack.insertTimeRange(
			CMTimeRange(start: .init(seconds: 0, preferredTimescale: 600), duration: duration),
			of: assetTrack,
			at: .init(seconds: 0, preferredTimescale: 600)
		)
		/**
		 Need to fill this track with content now or else the compositor will not get frames for this track even if we insertTimeRange of content later on. So this will fill it with the same data as the originalTrack
		 */
		try compositionFullPreviewTrack.insertTimeRange(
			CMTimeRange(start: .init(seconds: 0, preferredTimescale: 600), duration: duration),
			of: assetTrack,
			at: .init(seconds: 0, preferredTimescale: 600)
		)


		let instruction = AVMutableVideoCompositionInstruction()
		instruction.timeRange = CMTimeRange(start: .init(seconds: 0, preferredTimescale: 600), duration: duration)
		instruction.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: compositionOriginalTrack), AVMutableVideoCompositionLayerInstruction(assetTrack: compositionFullPreviewTrack)]

		videoComposition.frameDuration = frameDuration
		videoComposition.renderSize = trackSize
		videoComposition.instructions = [instruction]
		videoComposition.customVideoCompositorClass = PreviewVideoCompositor.self
	}

	/**
	 On a Change of fullPreview, update the fullPreview track inside the compositor. You must have had called [extractPreviewableAsset](AVAsset.extractPreviewableAsset) already on the asset or this will fail
	 */
	func updateFullPreviewTrack(settings: SettingsForFullPreview, newFullPreviewAsset asset: AVAsset) async throws {
		guard
			   let originalTrack = try await loadTrack(withTrackID: .originalVideoTrack),
			   let oldCompositionFullPreviewTrack = try await loadTrack(withTrackID: .fullPreviewVideoTrack),
			   let (fullPreviewTracks, fullPreviewAssetDuration) = try? await asset.load(.tracks, .duration),
			   let fullPreviewTrack = fullPreviewTracks.first else
		{
			throw PreviewableCompositionError.invalidState
		}
		removeTrack(oldCompositionFullPreviewTrack)
		guard let compositionFullPreviewTrack = addMutableTrack(withMediaType: .video, preferredTrackID: .fullPreviewVideoTrack) else {
			throw PreviewableCompositionError.couldNotAddTrack
		}

		let fullPreviewRange = settings.conversion.timeRange ?? 0...fullPreviewAssetDuration.seconds
		let fullPreviewStartTime = CMTime(seconds: fullPreviewRange.lowerBound, preferredTimescale: .video)
		compositionFullPreviewTrack.insertEmptyTimeRange(.init(start: .zero, duration: duration))
		/**
		 see [PreBakedFrames](PreBakedFrames) for why this is necessary
		 */
		let offsets = PreBakedFrames.Offsets(
			fullPreviewStartTime: fullPreviewStartTime,
			fullPreviewEndTime: CMTime(seconds: fullPreviewRange.upperBound, preferredTimescale: .video),
			originalTrackTimeRange: originalTrack.timeRange
		)

		try compositionFullPreviewTrack.insertTimeRange(
			CMTimeRange(start: offsets.start, end: fullPreviewAssetDuration - offsets.end),
			of: fullPreviewTrack,
			at: fullPreviewStartTime + offsets.start
		)
	}


	enum PreviewableCompositionError: Error {
		case invalidState
		case couldNotAddTrack
		case assetHasNoTracks
		case fullPreviewHasNoTracks
		case couldNotCreateTracks
	}
}
