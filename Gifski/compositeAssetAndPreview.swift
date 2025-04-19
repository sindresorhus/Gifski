//
//  compositeAssetAndPreview.swift
//  Gifski
//
//  Created by Michael Mulet on 4/18/25.
//

import Foundation
import AVFoundation

func compositeAssetAndPreview(
	modifiedAsset: AVAsset,
	previewAsset: AVAsset,
	previewRange maybePreviewRange: ClosedRange<Double>?,
) async throws -> GeneratedPreview {
	let composition = AVMutableComposition()
	let (modifiedAssetTracks, modifiedAssetDuration) = try await modifiedAsset.load(.tracks, .duration)
	guard let modifiedAssetTrack = modifiedAssetTracks.first else {
		throw CompositeAssetAndPreviewError.assetHasNoTracks
	}
	let (modifiedTrackSize, frameDuration) = try await modifiedAssetTrack.load(.naturalSize, .minFrameDuration)
	let (previewAssetTracks, previewAssetDuration) = try await previewAsset.load(.tracks, .duration)
	guard let previewTrack = previewAssetTracks.first else {
		throw CompositeAssetAndPreviewError.previewHasNoTracks
	}
	let previewTrackSize = try await previewTrack.load(.naturalSize)

	guard let compositionModifiedTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: .modifiedAssetTrackID),
		  let compositionPreviewTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: .previewAssetTrackID) else {
		throw CompositeAssetAndPreviewError.couldNotCreateTracks
	}

	try compositionModifiedTrack.insertTimeRange(
		CMTimeRange(start: .zero, duration: modifiedAssetDuration),
		of: modifiedAssetTrack,
		at: .zero
	)


	let previewRange = maybePreviewRange ?? 0...previewAssetDuration.seconds
	let previewStartTime = CMTime(seconds: previewRange.lowerBound, preferredTimescale: .video)
	let previewEndTime = CMTime(seconds: previewRange.upperBound, preferredTimescale: .video)



	try compositionPreviewTrack.insertTimeRange(
		CMTimeRange(start: .zero, duration: previewAssetDuration),
		of: previewTrack,
		at: previewStartTime
	)


	let videoComposition: AVMutableVideoComposition = {
		let videoComposition = AVMutableVideoComposition()

		videoComposition.frameDuration = frameDuration
		videoComposition.renderSize = modifiedTrackSize

		let modifiedAssetInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionModifiedTrack)
		let previewInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionPreviewTrack)


		let translationX = (modifiedTrackSize.width - previewTrackSize.width) / 2
		let translationY = (modifiedTrackSize.height - previewTrackSize.height) / 2
		let transform = CGAffineTransform(translationX: translationX, y: translationY)
		previewInstruction.setTransform(transform, at: .zero)


		modifiedAssetInstruction.setOpacity(1.0, at: .zero)
		previewInstruction.setOpacity(0.0, at: .zero)

		modifiedAssetInstruction.setOpacity(0.0, at: previewStartTime)
		previewInstruction.setOpacity(1.0, at: previewStartTime)


		modifiedAssetInstruction.setOpacity(1.0, at: previewEndTime)
		previewInstruction.setOpacity(0.0, at: previewEndTime)


		let mainInstruction = AVMutableVideoCompositionInstruction()
		mainInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
		mainInstruction.layerInstructions = [modifiedAssetInstruction, previewInstruction]

		videoComposition.instructions = [mainInstruction]
		return videoComposition
	}()

	let withoutPreviewVideoComposition: AVMutableVideoComposition = {
		let withoutPreviewInstruction = AVMutableVideoCompositionInstruction()
		withoutPreviewInstruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

		withoutPreviewInstruction.layerInstructions = [AVMutableVideoCompositionLayerInstruction(assetTrack: compositionModifiedTrack)]


		let withoutPreviewVideoComposition = AVMutableVideoComposition()
		withoutPreviewVideoComposition.frameDuration = frameDuration
		withoutPreviewVideoComposition.renderSize = modifiedTrackSize

		withoutPreviewVideoComposition.instructions = [withoutPreviewInstruction]
		return withoutPreviewVideoComposition
	}()

	return .init(
		previewAVAsset: composition,
		withPreviewVideoComposition: videoComposition,
		withoutPreviewVideoComposition: withoutPreviewVideoComposition
	)
}

struct GeneratedPreview {
	var previewAVAsset: AVMutableComposition
	var withPreviewVideoComposition: AVMutableVideoComposition
	var withoutPreviewVideoComposition: AVMutableVideoComposition
}

enum CompositeAssetAndPreviewError: Error {
	case assetHasNoTracks
	case previewHasNoTracks
	case couldNotCreateTracks
}
