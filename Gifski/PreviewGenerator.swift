//
//  PreviewGenerator.swift
//  Gifski
//
//  Created by Michael Mulet on 3/22/25.

import Foundation
import SwiftUI
import AVFoundation
/**
	This class handles the generation of all previews.
    It has two types, singleFrame and entireAnimation
    but both are very similar. and work the same way.
    Here is how:

	When settings update, or video time change we add a new
	preview to a queue which runs on a background thread.

	The queue has a depth of 1, so only the most recent
	preview will be generated. If a new preview is added
	before the current preview is generated, the current
	preview will be overwritten by the new preview.

	Once it is done generating the preview, it updates
	the previewImage property which is observed @Published

	Please note that when you generate a single frame
	preview, it will generate a preview of the closet
	frame in the animation, which may not be at the
	exact time you scrubbed to. This is because the
	frame rate of the animation is usually very low
	and the fame you scrubbed may not exist in the
	output GIF.
*/
final class PreviewGenerator: ObservableObject {
	@MainActor
	@Published var previewImage: PreviewImage?
	@MainActor
	@Published var imageBeingGeneratedNow = false

	enum GeneratorType {
		case singleFrame
		case entireAnimation
	}

	var type: GeneratorType

	init(type: GeneratorType) {
		self.type = type
	}



	enum PreviewGeneration {
		case oneFrame(atTime: Double)
		case entireAnimation
	}
	struct PreviewImage  {
		var image: NSImage
		var whatWasGenerated: PreviewGeneration
		var settingsAtGenerateTime: GIFGenerator.Conversion
	}

	private enum ImageDataType {
		case stillImage
		case animatedGIF
	}

	/// NSImages are not Sendable so we will
	/// just send the Data to the main thread
	/// and create the image there
	private struct PreviewImageData: Sendable {
		var imageData: Data
		var type: ImageDataType
		var whatWasGenerated: PreviewGeneration
		var settingsAtGenerateTime: GIFGenerator.Conversion

		func toPreviewImage() -> PreviewImage?{
			let image: NSImage
			switch type {
			case .animatedGIF:
				image = NSImage(data: imageData) ?? NSImage()
			case .stillImage:
				guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
						  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
						return nil
				}
				image = NSImage(cgImage: cgImage, size: .zero)
			}

			return PreviewImage(
				image: image,
				whatWasGenerated: self.whatWasGenerated,
				settingsAtGenerateTime: self.settingsAtGenerateTime
			)
		}
	}


	private enum CreatePreviewState {
		case idle
		/// If the state is running we may queue the next
		/// time to preview, which will render after
		/// we are done. Increase the serial number
		/// to indicate that a new preview must be drawn
		case running(whatToGenerate: PreviewGeneration,
					 settingsAtGenerateTime: GIFGenerator.Conversion,
					 previewSerialNumber: Int
		)
	}

	private var createPreviewState: CreatePreviewState = .idle {
		didSet {
			let isRunning: Bool
			switch createPreviewState {
			case .idle:
				isRunning = false
			case .running:
				isRunning = true
			}
			Task {@MainActor in
				self.imageBeingGeneratedNow = isRunning
			}
		}
	}

	private enum PreviewResult{
		case new_image(image: PreviewImageData)
		case no_change
	}

	/// This function spawns the createPreviewThread if none exists.
	/// If one does exist, it will add the most recent time to a queue to
	/// be generated later. It will overwrite the most recent queued item
	/// so only the most recent time will generate a preview.
	@MainActor
	func onCurrentTimeDidChange(currentTime: Double, conversionSettings: GIFGenerator.Conversion)  {
		switch type {
		case .entireAnimation:
			/// Only create new frames
			/// on scrub if you are a
			/// single frames type
			return
		case .singleFrame:
			break
		}

		let previewSerialNumber: Int
		let wasIdleBeforeThisFunctionCall: Bool
		switch createPreviewState {
		case .idle:
			wasIdleBeforeThisFunctionCall = true
			previewSerialNumber = 0

		case .running( _, _, let oldPreviewSerialNumber):
			wasIdleBeforeThisFunctionCall = false
			previewSerialNumber = oldPreviewSerialNumber + 1
		}

		createPreviewState = .running(
			whatToGenerate: .oneFrame(atTime: currentTime),
			settingsAtGenerateTime: conversionSettings,
			previewSerialNumber: previewSerialNumber
		)
		if wasIdleBeforeThisFunctionCall {
			Task(priority: .utility) {
				await self.createPreviewBackgroundThreadLoop()
			}
		}
	}

	@MainActor
	func onSettingsDidChangeGeneratePreview(conversionSettings: GIFGenerator.Conversion){
		let previewSerialNumber: Int
		let wasIdleBeforeThisFunctionCall: Bool
		switch createPreviewState {
		case .idle:
			wasIdleBeforeThisFunctionCall = true
			previewSerialNumber = 0

		case .running( _, _, let oldPreviewSerialNumber):
			wasIdleBeforeThisFunctionCall = false
			previewSerialNumber = oldPreviewSerialNumber + 1
		}

		let whatToGenerate: PreviewGeneration
		switch type {
		case .entireAnimation:
			whatToGenerate = .entireAnimation
		case .singleFrame:
			/// We don't have a preview, so don't
			/// bother updating nothing
			guard let previewImage else {
				return
			}
			whatToGenerate = previewImage.whatWasGenerated
		}
		createPreviewState = .running(
			whatToGenerate: whatToGenerate,
			settingsAtGenerateTime: conversionSettings,
			previewSerialNumber: previewSerialNumber
		)

		if wasIdleBeforeThisFunctionCall {
			Task(priority: .utility) {
				await self.createPreviewBackgroundThreadLoop()
			}
		}
	}


	/// This will use GiFGenerate To generate a new preview image at a particular
	///  time or of the entire animation
	private func generatePreviewImage(
		whatToGenerate: PreviewGeneration,
		settingsAtGenerateTime: GIFGenerator.Conversion,
		oldPreviewImage: PreviewImage?
	) async -> PreviewResult? {
		switch whatToGenerate {
		case .entireAnimation:
			if case .entireAnimation = oldPreviewImage?.whatWasGenerated,
			   oldPreviewImage?.settingsAtGenerateTime == settingsAtGenerateTime
			{
				return .no_change
			}
			let data = try? await GIFGenerator.run(settingsAtGenerateTime) { _ in
				///no-op
			}

			guard let data
				   else {
				return nil
			}
			return .new_image(image: .init(
				imageData: data,
				type: .animatedGIF,
				whatWasGenerated: whatToGenerate,
				settingsAtGenerateTime: settingsAtGenerateTime
			))
		case .oneFrame(let previewTimeToGenerate):
			guard let frameRange = settingsAtGenerateTime.timeRange else {
				/// Don't have a frame range at all
				///  don't produce a preview GIF
				return nil
			}
			guard let frameRate = settingsAtGenerateTime.frameRate else {
				return nil
			}
			/// We want to generate 1 frame
			/// we have currentFrameSettings.frameRate frames/second
			/// or 1/currentFrameSettings.frameRate seconds/frame
			/// then multiply by 1 frame to the duration of one frame
			let duration_of_one_frame: Double = 1 / (frameRate.toDouble)
			/// Line up the current time to a frame that will
			/// be generated the generator
			let frame_number = ((previewTimeToGenerate - frameRange.lowerBound) / duration_of_one_frame).rounded(.down)

			let start = frame_number * duration_of_one_frame + frameRange.lowerBound

			if let oldPreviewImage,
			   oldPreviewImage.settingsAtGenerateTime == settingsAtGenerateTime,
			   case let .oneFrame(oldPreviewImageTimestamp) = oldPreviewImage.whatWasGenerated,
			   oldPreviewImageTimestamp == start
			{
				return .no_change
			}
			var currentFrameSettings = settingsAtGenerateTime
			/// Set the frame Rate artificially high
			/// because the GifGenerator may fail
			/// to run if near the end and less than
			/// one frame is pushed through
			currentFrameSettings.frameRate = 18
			/// Generate an average of 2.5 frames
			/// GIFGenerator fails if generating only 1
			/// frame. So le'ts make sure at least 2 frames
			/// generate
			currentFrameSettings.timeRange = start...(start + 2.5 / 18.0)

			let data = try? await GIFGenerator.run(currentFrameSettings) { _ in
				///no-op
			}

			guard let data else {
				return nil
			}


			return .new_image(
				image: .init(
					imageData: data,
					type: .stillImage,
					whatWasGenerated: .oneFrame(atTime: start),
					settingsAtGenerateTime: settingsAtGenerateTime
				)
			)
		}
	}

	/// This function runs in a loop to create previews.
	///  It is intended to run this on a background thread
	///  using Task(priority: .utility)
	private func createPreviewBackgroundThreadLoop() async {
		///
		/// Loop Explanation:
		/// Generate the top frame in the queue.
		/// Then check for additional frames, if there are any
		/// generate the next frame in the queue, in an infinite
		/// loop.
		while true {
			let createPreviewStateAtStartOfLoop: CreatePreviewState = self.createPreviewState
			switch createPreviewStateAtStartOfLoop {
			case .idle:
				/// No more work. End the loop.
				return
			case .running(
				let whatToGenerate,
				let settingsAtGenerateTime,
				let serialNumberOfPreview
			):
				let data = await generatePreviewImage(
					whatToGenerate: whatToGenerate,
					settingsAtGenerateTime: settingsAtGenerateTime,
					oldPreviewImage: self.previewImage
				)
				///This may be different than the start of the loop as we may
				///have received requests during the time it took to generate
				let createPreviewStateAfterGeneratingPreview: CreatePreviewState = self.createPreviewState

				switch createPreviewStateAfterGeneratingPreview {
				case .idle:
					/// This case should never happen
					/// because the only time we set the createPreviewState
					/// to .idle is in the case below:
					assertionFailure()
					switch data {
					case .no_change:
						return
					case nil:
						Task {
							@MainActor in
							self.previewImage = nil
						}
					case .new_image(let newImage):
						Task {
							@MainActor in
							previewImage = newImage.toPreviewImage()
						}
					}
				case .running(_, _, let serialNumberAfterPreview):
					let previewIsFinished = serialNumberOfPreview == serialNumberAfterPreview
						switch data {
						case .no_change:
							break
						case nil:
							Task {
								@MainActor in
								self.previewImage = nil
							}
						case .new_image(let newImage):
							Task {
								@MainActor in
								previewImage = newImage.toPreviewImage()
							}
						}

					guard previewIsFinished else {
						///Preview is not finished
						///resume the loop and process
						///the next frame
						continue
					}
					/// Preview is finished. End the createPreviewFunction
					self.createPreviewState = .idle
					return
				}
			}
		}
	}
}
