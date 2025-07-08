import Foundation
import AVKit
import SwiftUI

struct ExportModifiedVideoView: View {
	@Environment(AppState.self) private var appState
	@Binding var state: State
	let sourceURL: URL

	var body: some View {
		ZStack{}
			.sheet(isPresented: isProgressSheetPresented) {
				ProgressView()
			}
			.fileExporter(
				isPresented: isFileExporterPresented,
				item: exportableMP4,
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
				"Export video Limitation",
				message: "Exporting a video with audio is not supported. The audio track will be ignored.",
				isPresented: isAudioWarningPresented
			)
	}

	private var exportableMP4: ExportableMP4? {
		guard case let .exported(url) = state else {
			return nil
		}
		return ExportableMP4(url: url)
	}

	private var defaultExportModifiedFileName: String {
		sourceURL.filenameWithoutExtension + " modified.mp4"
	}

	private var isProgressSheetPresented: Binding<Bool> {
		.init(
			get: {
				if case .exporting = state {
					return true
				}
				return false
			},
			set: {
				guard !$0,
					  case let .exporting(task) = state else {
					return
				}
				task.cancel()
				state = .idle
			}
		)
	}

	private var isFileExporterPresented: Binding<Bool> {
		.init(
			get: {
				if case .exported = state {
					return true
				}
				return false
			},
			set: {
				guard !$0,
				   case let .exported(url) = state else {
					return
				}
				try? FileManager.default.removeItem(at: url)
				state = .idle
			}
		)
	}

	private var isAudioWarningPresented: Binding<Bool> {
		.init(
			get: {
				if case .audioWarning = state {
					return true
				}
				return false
			},
			set: {
				guard !$0,
					  case .audioWarning = state else{
					return
				}
				appState.onExportAsVideo?()
			}
		)
	}

	enum State {
		case idle
		case audioWarning
		case exporting(Task<Void, Never>)
		case exported(URL)
	}

	enum Error: Swift.Error {
		case unableToCreateExportSession
		case unableToAddCompositionTrack

		var errorDescription: String? {
			switch self {
			case .unableToCreateExportSession:
				"Unable to create an export session for the video."
			case .unableToAddCompositionTrack:
				"Failed to add a composition track to the video."
			}
		}
	}
}

/**
 Convert a source video to an `.mp4` using the same scale, speed, and crop as the exported `.gif`
- Returns: Temporary URL of the exported video
 */
func exportModifiedVideo(conversion: GIFGenerator.Conversion) async throws -> URL {
	let (composition, compositionVideoTrack) = try await createComposition(
		conversion: conversion
	)
	let videoComposition = try await createVideoComposition(
		compositionVideoTrack: compositionVideoTrack,
		conversion: conversion
	)
	let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent( "\(UUID().uuidString).mp4")
	guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
		throw ExportModifiedVideoView.Error.unableToCreateExportSession
	}
	exportSession.videoComposition = videoComposition
	try await exportSession.export(to: outputURL, as: .mp4)
	return outputURL
}

/**
Creates the mutable composition along with the video track inserted
 */
private func createComposition(
	conversion: GIFGenerator.Conversion,
) async throws -> (AVMutableComposition, AVMutableCompositionTrack) {
	let composition = AVMutableComposition()
	guard let compositionTrack = composition.addMutableTrack(
		withMediaType: .video,
		preferredTrackID: kCMPersistentTrackID_Invalid
	) else {
		throw ExportModifiedVideoView.Error.unableToAddCompositionTrack
	}
	try compositionTrack.insertTimeRange(
		try await conversion.exportModifiedVideoTimeRange,
		of: try await conversion.firstVideoTrack,
		at: .zero
	)
	return (composition, compositionTrack)
}

/**
Create an  `AVMutableVideoComposition` that wll scale, translate, and crop the `compositionVideoTrack`
 */
private func createVideoComposition(
	compositionVideoTrack: AVMutableCompositionTrack,
	conversion: GIFGenerator.Conversion
) async throws -> AVMutableVideoComposition {
	let videoComposition = AVMutableVideoComposition()

	let cropRectInPixels = try await conversion.cropRectInPixels
	videoComposition.renderSize = cropRectInPixels.size
	videoComposition.frameDuration = try await compositionVideoTrack.load(.minFrameDuration)

	let instruction = AVMutableVideoCompositionInstruction()
	// The instruction time range must be greater than or equal to the video and there is no penality for making it longer, so add 1.0 second to the duration just to be safe
	instruction.timeRange = CMTimeRange(start: .zero, duration: .init(seconds: try await conversion.videoWithoutBounceDuration.toTimeInterval + 1.0, preferredTimescale: .video))

	let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
	let scale = try await conversion.scale
	layerInstruction.setTransform(.init(scaledBy: scale).translated(by: -cropRectInPixels.origin / scale), at: .zero)
	instruction.layerInstructions = [layerInstruction]

	videoComposition.instructions = [instruction]
	return videoComposition
}

private struct ExportableMP4: Transferable {
	let url: URL
	static var transferRepresentation: some TransferRepresentation {
		FileRepresentation(exportedContentType: .mpeg4Movie) { .init($0.url) }
			.suggestedFileName { $0.url.filename }
	}
}
