import Foundation
import AVFoundation
import SwiftUI

struct ExportModifiedVideoView: View {
	@Environment(AppState.self) private var appState
	@Binding var state: ExportModifiedVideoState
	let sourceURL: URL

	@Binding var isAudioWarningPresented: Bool

	var body: some View {
		ZStack {} // Intentionally using this so it doesn't take up any space.
			.sheet(isPresented: isProgressSheetPresented) {
				ProgressView()
			}
			.fileExporter(
				isPresented: isFileExporterPresented,
				item: exportableModifiedVideo,
				defaultFilename: defaultExportModifiedFileName
			) {
				do {
					let url = try $0.get()
					try? url.setAppAsItemCreator()
				} catch {
					appState.error = error
				}
			}
			.fileDialogCustomizationID("export")
			.fileDialogMessage("Choose where to save the video")
			.fileDialogConfirmationLabel("Save")
			.alert2(
				"Export Video Limitation",
				message: "Exporting a video with audio is not supported. The audio track will be ignored.",
				isPresented: $isAudioWarningPresented
			)
	}

	private var exportableModifiedVideo: ExportableModifiedVideo? {
		state.finishedURL.map(ExportableModifiedVideo.init)
	}

	private var defaultExportModifiedFileName: String {
		let fileExtension = state.finishedURL?.pathExtension ?? "mp4"
		return "\(sourceURL.filenameWithoutExtension) modified.\(fileExtension)"
	}

	private var isProgressSheetPresented: Binding<Bool> {
		.init(
			get: {
				guard
					!isAudioWarningPresented,
					case let .exporting(_, shouldShowProgressSheet) = state else {
					return false
				}
				return shouldShowProgressSheet
			},
			set: {
				guard
					!$0,
					case let .exporting(task, _) = state else {
					return
				}
				task.cancel()
				state = .idle
			}
		)
	}

	private var isFileExporterPresented: Binding<Bool> {
		.init(
			get: { state.isFinished && !isAudioWarningPresented },
			set: {
				guard
					!$0,
					let url = state.finishedURL else {
					return
				}
				try? url.delete()
				state = .idle
			}
		)
	}

	enum Error: LocalizedError {
		case unableToExportAsset
		case unableToCreateExportSession
		case unableToAddCompositionTrack

		var errorDescription: String? {
			switch self {
			case .unableToExportAsset:
				"Unable to export the asset because it is not compatible with the current device."
			case .unableToCreateExportSession:
				"Unable to create an export session for the video."
			case .unableToAddCompositionTrack:
				"Failed to add a composition track to the video."
			}
		}
	}
}

enum ExportModifiedVideoState {
	case idle
	case exporting(Task<Void, Never>, shouldShowProgressSheet: Bool)
	case finished(URL)
}

extension ExportModifiedVideoState: Equatable {
	static func == (lhs: Self, rhs: Self) -> Bool {
		switch (lhs, rhs) {
		case (.idle, .idle):
			true
		// Intentionally ignores Task identity - we only care about the exporting state, not which specific task.
		case (.exporting(_, let lhsShouldShowProgressSheet), .exporting(_, let rhsShouldShowProgressSheet)):
			lhsShouldShowProgressSheet == rhsShouldShowProgressSheet
		case (.finished(let lhsURL), .finished(let rhsURL)):
			lhsURL == rhsURL
		default:
			false
		}
	}
}

extension ExportModifiedVideoState {
	var isExporting: Bool {
		switch self {
		case .exporting:
			true
		default:
			false
		}
	}

	var isFinished: Bool {
		switch self {
		case .finished:
			true
		default:
			false
		}
	}

	var finishedURL: URL? {
		guard case let .finished(url) = self else {
			return nil
		}

		return url
	}

	/**
	Update progress sheet visibility if the state is currently exporting.
	- Returns: Whether the state is still exporting.
	*/
	mutating func updateProgressSheetVisibility(_ shouldShowProgressSheet: Bool) -> Bool {
		guard case let .exporting(task, _) = self else {
			return false
		}

		self = .exporting(
			task,
			shouldShowProgressSheet: shouldShowProgressSheet
		)

		return true
	}
}

/**
Convert a source video using the same scale, speed, and crop as the exported `.gif`.

Alpha-capable sources (for example, ProRes 4444) are exported as HEVC with alpha in a `.mov` to preserve transparency. Everything else is exported as an `.mp4`.
- Returns: Temporary URL of the exported video.
*/
func exportModifiedVideo(conversion: GIFGenerator.Conversion) async throws -> URL {
	let (composition, compositionVideoTrack, sourceVideoTrack) = try await createComposition(
		conversion: conversion
	)

	let hasAlpha = try await sourceVideoTrack.hasAlphaChannel
	let preset = hasAlpha ? AVAssetExportPresetHEVCHighestQualityWithAlpha : AVAssetExportPresetHighestQuality
	let fileType: AVFileType = hasAlpha ? .mov : .mp4
	let fileExtension = hasAlpha ? "mov" : "mp4"

	let videoComposition = try await createVideoComposition(
		compositionVideoTrack: compositionVideoTrack,
		sourceVideoTrack: sourceVideoTrack,
		conversion: conversion,
		preservingAlpha: hasAlpha
	)
	let outputURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(fileExtension)")

	let presets = AVAssetExportSession.allExportPresets()
	guard presets.contains(preset) else {
		throw ExportModifiedVideoView.Error.unableToCreateExportSession
	}
	guard await AVAssetExportSession.compatibility(ofExportPreset: preset, with: composition, outputFileType: fileType) else {
		throw ExportModifiedVideoView.Error.unableToCreateExportSession
	}

	guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
		throw ExportModifiedVideoView.Error.unableToCreateExportSession
	}
	exportSession.shouldOptimizeForNetworkUse = true
	exportSession.videoComposition = videoComposition
	try await exportSession.export(to: outputURL, as: fileType)
	return outputURL
}

/**
Creates the mutable composition along with the video track inserted.
*/
private func createComposition(
	conversion: GIFGenerator.Conversion
) async throws -> (composition: AVMutableComposition, compositionVideoTrack: AVMutableCompositionTrack, sourceVideoTrack: AVAssetTrack) {
	let composition = AVMutableComposition()

	guard let compositionVideoTrack = composition.addMutableTrack(
		withMediaType: .video,
		preferredTrackID: kCMPersistentTrackID_Invalid
	) else {
		throw ExportModifiedVideoView.Error.unableToAddCompositionTrack
	}
	let sourceVideoTrack = try await conversion.firstVideoTrack
	try compositionVideoTrack.insertTimeRange(
		try await conversion.exportModifiedVideoTimeRange,
		of: sourceVideoTrack,
		at: .zero
	)
	compositionVideoTrack.preferredTransform = try await conversion.geometry(for: sourceVideoTrack).preferredTransform
	// Return the source track too because composition tracks do not reliably carry the natural-size geometry needed by the shared crop/scale code.
	return (composition, compositionVideoTrack, sourceVideoTrack)
}

/**
Creates an `AVVideoComposition` that will scale, translate, and crop the `compositionVideoTrack`. When `preservingAlpha` is set, it uses the Core Image based compositor that keeps the source's transparency.
*/
private func createVideoComposition(
	compositionVideoTrack: AVMutableCompositionTrack,
	sourceVideoTrack: AVAssetTrack,
	conversion: GIFGenerator.Conversion,
	preservingAlpha: Bool
) async throws -> AVVideoComposition {
	let frameDuration = try await compositionVideoTrack.videoCompositionFrameDuration

	if preservingAlpha {
		return try await conversion.alphaPreservingVideoComposition(
			for: compositionVideoTrack,
			usingGeometryOf: sourceVideoTrack,
			frameDuration: frameDuration,
			preservesSourceFrameTiming: true
		)
	}

	// The instruction time range must be greater than or equal to the video and there is no penalty for making it longer, so add 1.0 second to the duration just to be safe
	let timeRange = CMTimeRange(start: .zero, duration: .init(seconds: try await conversion.videoWithoutBounceDuration.toTimeInterval + 1.0, preferredTimescale: .video))
	return try await conversion.videoComposition(
		for: compositionVideoTrack,
		usingGeometryOf: sourceVideoTrack,
		timeRange: timeRange,
		frameDuration: frameDuration,
		preservesSourceFrameTiming: true
	)
}

private struct ExportableModifiedVideo: Transferable {
	let url: URL
	static var transferRepresentation: some TransferRepresentation {
		// `.movie` so it covers both the `.mp4` and the alpha `.mov` output.
		FileRepresentation(exportedContentType: .movie) { .init($0.url) }
			.suggestedFileName { $0.url.filename }
	}
}
