//
//  PreviewGenerator.swift
//  Gifski
//
//  Created by Michael Mulet on 3/22/25.

import Foundation
import SwiftUI
import AVFoundation

@Observable
final class PreviewGenerator {
	@MainActor
	var previewImage: PreviewImage?

	private var previewImageCommand: PreviewCommand?
	@MainActor
	var imageBeingGeneratedNow = false

	private var commandStream = LatestCommandAsyncStream()

	enum PreviewImage {
		case image(NSImage)
		case tooFewFrames
	}

	init() {
		Task(priority: .utility) {
			for await item in commandStream {
				guard commandStream.commandIsLatest(command: item) else {
					continue
				}
				if previewImageCommand == item.command {
					/**
					 Don't regenerate if it's the same
					 */
					continue
				}
				Task {
					@MainActor in
					self.imageBeingGeneratedNow = true
				}
				defer {
					Task {
						@MainActor in

						self.imageBeingGeneratedNow = false
					}
				}
				let data = await generatePreviewImage(
					previewCommand: item.command
				)
				Task {
					@MainActor in
					self.previewImage = data?.toPreviewImage()
				}

				self.previewImageCommand = previewImageCommand
			}
		}
	}


	func generatePreview(command: PreviewCommand)  {
		self.commandStream.add(command)
	}

	/**
	 NSImages are not Sendable so we will
	 just send the Data to the main thread
	 and create the image there
	 */
	private enum PreviewImageData: Sendable {
		case stillImage(Data)
		case animatedGIF(Data)
		case tooFewFrames

		func toPreviewImage() -> PreviewImage?{
			let image: NSImage
			switch self {
			case .tooFewFrames:
				return .tooFewFrames
			case .animatedGIF(let imageData):
				image = NSImage(data: imageData) ?? NSImage()
			case .stillImage(let imageData):
				guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
					  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
					return nil
				}
				image = NSImage(cgImage: cgImage, size: .zero)
			}
			return .image(image)
		}
	}

	struct PreviewCommand: Sendable, Equatable {
		let whatToGenerate: PreviewGeneration
		let settingsAtGenerateTime: GIFGenerator.Conversion

		enum PreviewGeneration: Equatable {
			case oneFrame(atTime: Double)
			case entireAnimation
		}
	}

	/**
	 This will use GiFGenerate To generate a new preview image at a particular
	 time or of the entire animation
	 */
	private func generatePreviewImage(
		previewCommand: PreviewCommand
	) async -> PreviewImageData? {
		guard let frameRange = previewCommand.settingsAtGenerateTime.timeRange,
			  let frameRate = previewCommand.settingsAtGenerateTime.frameRate else {
			return nil
		}

		let duration_of_one_frame: Double = 1 / (frameRate.toDouble)

		switch previewCommand.whatToGenerate {
		case .entireAnimation:

			guard frameRange.upperBound - frameRange.lowerBound >= duration_of_one_frame * 2.0 else {
				return .tooFewFrames
			}

			let data = try? await GIFGenerator.run(previewCommand.settingsAtGenerateTime) { _ in
				/**
				 no-op
				 */
			}
			guard let data
				   else {
				return nil
			}
			return  .animatedGIF(data)
		case .oneFrame(let previewTimeToGenerate):
			guard let videoTrack = try? await previewCommand.settingsAtGenerateTime.asset.firstVideoTrack,
				  let videoTimeRange = try? await videoTrack.load(.timeRange)
			else {
				return nil
			}

			/**
			 Line up the current time to a frame that will
			 be generated the generator
			 */
			let frame_number = ((previewTimeToGenerate - frameRange.lowerBound) / duration_of_one_frame).rounded(.down)

			/**
			 Make sure we have enough frames to work with
			 */
			let start = min(
				videoTimeRange.end.seconds - 2.5 * duration_of_one_frame,
				frame_number * duration_of_one_frame + frameRange.lowerBound
			)

			var currentFrameSettings = previewCommand.settingsAtGenerateTime

			/**
			 Set the frame rate artificially high
			 because the GifGenerator may fail
			 to run if near the end and less than
			 one frame is pushed through
			 */
			currentFrameSettings.frameRate = currentFrameSettings.frameRate ?? 18

			/**
			 Generate an average of 2.5 frames
			 GIFGenerator fails if generating only 1
			 frame. So le'ts make sure at least 2 frames
			 generate
			 */
			currentFrameSettings.timeRange = start...(start + 2.5 / Double(currentFrameSettings.frameRate ?? 18))
			let data = try? await GIFGenerator.run(currentFrameSettings) { _ in
				/**
				 no-op
				 */
			}
			guard let data else {
				return nil
			}
			return .stillImage(data)
		}
	}

	/**
	 An async Stream that will yield when a new item is added,
	 but keeps an up to date sequence of items so you can
	 know if you are processing the latest item inserted into
	 the stream.
	 */
	private struct LatestCommandAsyncStream: AsyncSequence {
		fileprivate struct SequencedPreviewCommand {
			let command: PreviewCommand
			let sequenceNumber: Int
		}
		func commandIsLatest(command: SequencedPreviewCommand) -> Bool {
			command.sequenceNumber == latestItemSequenceNumber
		}
		private var latestItemSequenceNumber = -1
		private var stream: AsyncStream<SequencedPreviewCommand>!
		private var continuation: AsyncStream<SequencedPreviewCommand>.Continuation!

		init() {
			self.stream = AsyncStream { continuation in
				self.continuation = continuation
			}
		}
		mutating func add(_ command: PreviewCommand) {
			latestItemSequenceNumber += 1
			continuation.yield(
				.init(command: command, sequenceNumber: latestItemSequenceNumber)
			)
		}
		func makeAsyncIterator() -> AsyncStream<SequencedPreviewCommand>.Iterator {
			stream.makeAsyncIterator()
		}
	}
}
