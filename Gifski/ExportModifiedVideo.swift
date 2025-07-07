import Foundation
import AVKit
import SwiftUI

struct ExportModifiedVideo: View {
	@Environment(AppState.self) private var appState
	@Environment(\.dismiss) private var dismiss
	let input: Self.Input
	@State private var state = ConvertState.generating(progress: 0)

	var body: some View {
		VStack(spacing: 20) {
			switch state {
			case let .empty(error: error):
				if let error {
					Text(error)
				}
				Button("Cancel") {
					dismiss()
				}
			case .generating, .finished:
				ProgressView()
				if input.gifDuration >= 20 {
					Button("Cancel") {
						dismiss()
					}
				}
			}
		}
		.padding()
		.task(priority: .medium) {
			do {
				let task = Self.exportModifiedVideo(input: input)
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

				self.state = .finished(
					filename: input.conversion.sourceURL.filenameWithoutExtension + " modified.mp4",
					url: outputURL,
					player: AVPlayer(url: outputURL),
					aspectRatio: aspectRatio
				)
			} catch {
				if Task.isCancelled || error.isCancelled {
					return
				}
				self.state = .empty(error: error.localizedDescription)
			}
		}
		.fileExporter(
			isPresented: .init(get: {
				if case .finished = state {
					return true
				}
				return false
			}, set: { _ in }),
			item: exportableMP4,
			defaultFilename: defaultFileName
		) {
			do {
				let url = try $0.get()
				try? url.setAppAsItemCreator()
				dismiss()
			} catch {
				state = .empty(error: error.localizedDescription)
			}
		} onCancellation: {
			dismiss()
		}
		.fileDialogCustomizationID("export")
		.fileDialogMessage("Choose where to save the video")
		.fileDialogConfirmationLabel("Save")
		.onDisappear {
			removeTempExport()
		}
	}
	struct Input {
		let conversion: GIFGenerator.Conversion
		let audioAssets: [AVAsset]
		let gifDuration: Double

		init(conversion: GIFGenerator.Conversion, audioAssets: [AVAsset], speed: Double, assetDuration: TimeInterval) {
			self.conversion = conversion
			self.audioAssets = audioAssets
			let range = self.conversion.timeRange ?? 0...assetDuration
			gifDuration = range.length * speed
		}
	}

	private var defaultFileName: String {
		switch state {
		case let .finished(filename, _, _, _):
			filename
		default:
			"Untitled.mp4"
		}
	}

	private func removeTempExport() {
		exportURL.map {
			try? FileManager.default.removeItem(at: $0)
		}
	}

	private var exportableMP4: ExportableMP4? {
		exportURL.map {
			ExportableMP4(url: $0)
		}
	}

	private var exportURL: URL? {
		switch state {
		case let .finished(_, url, _, _):
			url
		default:
			nil
		}
	}

	private enum ConvertState: Equatable, Sendable {
		case empty(error: String?)
		case generating(progress: Double)
		case finished(filename: String, url: URL, player: AVPlayer, aspectRatio: Double)
	}

	private static func exportModifiedVideo(input: Input) -> ProgressableTask<Double, (URL, Double)> {
		ProgressableTask { progressContinuation in
			let exportComposition = try await ExportComposition(input: input)

			let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent( "\(UUID().uuidString).mp4")

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
			try await exportSession.export(to: outputURL, as: .mp4)
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

		init(input: ExportModifiedVideo.Input) async throws {
			let conversion = input.conversion
			let asset = conversion.asset
			let duration = try await asset.load(.duration)
			guard let videoTrack = try await asset.firstVideoTrack else {
				throw Error.noVideoTrack
			}

			let (trackSize, frameDuration) = try await videoTrack.load(.naturalSize, .minFrameDuration)
			composition = AVMutableComposition()
			let timeRange = (conversion.timeRange ?? 0...duration.seconds).cmTimeRange

			let compositionTrack = try await Self.insertTrack(composition: composition, asset: asset, trackType: .video, timeRange: timeRange)
			for audioAsset in input.audioAssets {
				try await Self.insertTrack(composition: composition, asset: audioAsset, trackType: .audio, timeRange: timeRange)
			}

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

		@discardableResult
		private static func insertTrack(composition: AVMutableComposition, asset: AVAsset, trackType: TrackType, timeRange: CMTimeRange) async throws -> AVMutableCompositionTrack{
			guard let compositionTrack = composition.addMutableTrack(
				withMediaType: trackType.mediaType,
				preferredTrackID: kCMPersistentTrackID_Invalid
			) else {
				throw Error.unableToAddCompositionTrack
			}
			let track = try await trackType.track(for: asset)
			try compositionTrack.insertTimeRange(
				timeRange,
				of: track,
				at: .zero
			)
			return compositionTrack
		}

		private enum TrackType {
			case audio
			case video

			var mediaType: AVMediaType {
				switch self {
				case .audio:
					.audio
				case .video:
					.video
				}
			}

			func track(for asset: AVAsset) async throws -> AVAssetTrack {
				guard let track = try await _track(for: asset) else {
					switch self {
					case .audio:
						throw ExportComposition.Error.noAudioTrack
					case .video:
						throw ExportComposition.Error.noVideoTrack
					}
				}
				return track
			}

			private func _track(for asset: AVAsset) async throws -> AVAssetTrack? {
				switch self {
				case .video:
					try await asset.firstVideoTrack
				case .audio:
					try await asset.firstAudioTrack
				}
			}
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
			layerInstruction.setTransform(.init(scaledBy: scale).translated(by: -cropRectInPixels.origin / scale), at: .zero)
			instruction.layerInstructions = [layerInstruction]

			videoComposition.instructions = [instruction]
			return videoComposition
		}
		enum Error: Swift.Error {
			case noVideoTrack
			case noAudioTrack
			case unableToAddCompositionTrack


			var errorDescription: String? {
				switch self {
				case .noVideoTrack:
					"The video asset does not contain a video track."
				case .noAudioTrack:
					"The audio asset does not contain an audio track."
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

	private struct ExportableMP4: Transferable {
		let url: URL
		static var transferRepresentation: some TransferRepresentation {
			FileRepresentation(exportedContentType: .mpeg4Movie) { .init($0.url) }
				.suggestedFileName { $0.url.filename }
		}
	}
}
