import Foundation
import AVKit
import SwiftUI

struct ExportModifiedVideo: View {
	@Environment(AppState.self) private var appState
	@Binding var exportID: UUID?
	@State private var state = ConvertState.empty(error: nil)
	@State private var isFileExporterPresented = false
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(spacing: 20) {
			switch state {
			case let .empty(error: error):
				if let error {
					Text(error)
				}
			case let .generating(progress: progress):
				ExportProgress(text: "Exporting", progress: progress)

			case let .finished(url, aspectRatio):
				VideoPlayer(player: AVPlayer(url: url))
					.aspectRatio(aspectRatio, contentMode: .fit)
					.clipShape(RoundedRectangle(cornerRadius: 8))
				Button("Save") {
					isFileExporterPresented = true
				}
				.keyboardShortcut("s")
			}
		}
		.frame(width: ExportProgress.width + 50, height: ExportProgress.height + 50)
		.padding()
		.task(priority: .medium) {
			do {
				guard let exportID,
					  let conversion = appState.videoExports[exportID] else {
					self.state = .empty(error: "Could not find video to export")
					return
				}
				let task = Self.exportModifiedVideo(conversion: conversion)
				self.state = .generating(progress: 0)
				await withTaskCancellationHandler {
					for await progress in task.progress {
						self.state = .generating(progress: progress)
					}
				} onCancel: {
					task.cancel()
				}
				try Task.checkCancellation()
				let (outputURL, aspectRatio) = try await task.value
				try Task.checkCancellation()

				// let the animation play
				self.state = .generating(progress: 1)
				try await Task.sleep(for: .seconds(1.0))

				self.state = .finished(url: outputURL, aspectRatio: aspectRatio)
			} catch {
				if Task.isCancelled || error.isCancelled {
					return
				}
				self.state = .empty(error: error.localizedDescription)
			}
		}
		.fileExporter(isPresented: $isFileExporterPresented, item: exportableMOV, defaultFilename: defaultFileName) {
			do {
				let url = try $0.get()
				try? url.setAppAsItemCreator()
				if let exportURL {
					try FileManager.default.removeItem(at: exportURL)
				}
				dismiss()
				state = .empty(error: nil)
			} catch {
				state = .empty(error: error.localizedDescription)
			}
		}
		.fileDialogCustomizationID("export")
		.fileDialogMessage("Choose where to save the video")
		.fileDialogConfirmationLabel("Save")
	}

	private var defaultFileName: String {
		switch state {
		case let .finished(url, _):
			url.filename
		default:
			"Untitled.mov"
		}
	}

	private var exportableMOV: ExportableMOV? {
		exportURL.map {
			ExportableMOV(url: $0)
		}
	}

	private var exportURL: URL? {
		switch state {
		case let .finished(url, _):
			url
		default:
			nil
		}
	}

	private enum ConvertState: Equatable, Sendable {
		case empty(error: String?)
		case generating(progress: Double)
		case finished(url: URL, aspectRatio: Double)
	}

	private static func exportModifiedVideo(conversion: GIFGenerator.Conversion) -> ProgressableTask<Double, (URL, Double)> {
		ProgressableTask { progressContinuation in
			let exportComposition = try await ExportComposition(conversion: conversion)

			let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent( conversion.sourceURL.filenameWithoutExtension + " modified.mov")

			try? FileManager.default.removeItem(at: outputURL)
			guard let exportSession = AVAssetExportSession(asset: exportComposition.composition, presetName: AVAssetExportPresetHighestQuality) else {
				throw Error.unableToCreateExportSession
			}
			exportSession.videoComposition = exportComposition.videoComposition

			let progressTask = Task {
				let progressStream = exportSession.states(updateInterval: 0.1)
				for await exportState in progressStream {
					try Task.checkCancellation()
					switch exportState {
					case let .exporting(progress: progress):
						progressContinuation.yield(progress.fractionCompleted)
					default:
						continue
					}
				}
			}
			defer {
				progressTask.cancel()
			}
			try await exportSession.export(to: outputURL, as: .mov)
			return (outputURL, exportComposition.aspectRatio)
		}
	}

	/**
	Creates a composition of the modified video (scaled, cropped, sped up,and with correct time range)
	*/
	private struct ExportComposition {
		let composition: AVMutableComposition
		let videoComposition: AVMutableVideoComposition
		let aspectRatio: Double

		init(conversion: GIFGenerator.Conversion) async throws {
			let asset = conversion.asset
			let duration = try await asset.load(.duration)
			guard let videoTrack = try await asset.firstVideoTrack else {
				throw Error.noVideoTrack
			}

			let (trackSize, frameDuration) = try await videoTrack.load(.naturalSize, .minFrameDuration)
			composition = AVMutableComposition()
			guard let compositionTrack = composition.addMutableTrack(
				withMediaType: .video,
				preferredTrackID: kCMPersistentTrackID_Invalid
			) else {
				throw Error.unableToAddCompositionTrack
			}
			try compositionTrack.insertTimeRange(
				(conversion.timeRange ?? 0...duration.seconds).cmTimeRange,
				of: videoTrack,
				at: .zero
			)

			let dimensions: CGSize = conversion.dimensions.map {
				.init(width: Double($0.0), height: Double($0.1))
			} ?? trackSize

			let cropRectInPixels = (conversion.crop ?? .initialCropRect).unnormalize(forDimensions: dimensions)
			videoComposition = Self.exportVideoComposition(
				compositionTrack: compositionTrack,
				cropRectInPixels: cropRectInPixels,
				scale: dimensions / trackSize,
				frameDuration: frameDuration,
				duration: duration
			)
			aspectRatio = cropRectInPixels.width / cropRectInPixels.height
		}

		/**
		 Create a composition that wll scale and translate the video layer.
		 */
		private static func exportVideoComposition(
			compositionTrack: AVMutableCompositionTrack,
			cropRectInPixels: CGRect,
			scale: CGSize,
			frameDuration: CMTime,
			duration: CMTime
		) -> AVMutableVideoComposition {
			let videoComposition = AVMutableVideoComposition()
			videoComposition.renderSize = cropRectInPixels.size
			videoComposition.frameDuration = frameDuration

			let instruction = AVMutableVideoCompositionInstruction()
			instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

			let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
			layerInstruction.setTransform(.init(scaledBy: scale).translatedBy(point: -cropRectInPixels.origin / scale), at: .zero)
			instruction.layerInstructions = [layerInstruction]

			videoComposition.instructions = [instruction]
			return videoComposition
		}
		enum Error: Swift.Error {
			case noVideoTrack
			case unableToAddCompositionTrack


			var errorDescription: String? {
				switch self {
				case .noVideoTrack:
					"The video asset does not contain a video track."
				case .unableToAddCompositionTrack:
					"Failed to add a composition track to the video."
				}
			}
		}
	}

	enum Error: Swift.Error {
		case unableToCreateExportSession
		var errorDescription: String? {
			switch self {
			case .unableToCreateExportSession:
				"Unable to create an export session for the video."
			}
		}
	}

	private struct ExportableMOV: Transferable {
		let url: URL
		static var transferRepresentation: some TransferRepresentation {
			FileRepresentation(exportedContentType: .quickTimeMovie) { .init($0.url) }
				.suggestedFileName { $0.url.filename }
		}
	}
}
