//
//  PreviewView.swift
//  Gifski
//
//  Created by Michael Mulet on 3/21/25.
//

import SwiftUI
import AVKit

@Observable
final class PreviewViewState {
	var shouldShowAnimation = false
	var viewUnderTrim: NSView?

	fileprivate var singleFramePreviewGenerator = PreviewGenerator()
	fileprivate var fullAnimationPreviewGenerator = PreviewGenerator()

	private var previewView: NSHostingView<PreviewView>!

	init() {
		previewView = NSHostingView(rootView: PreviewView(previewViewState: self))
	}
	@MainActor
	var isPlayButtonEnabled: Bool {
		if !showPreview {
			return true
		}
		return fullAnimationPreviewGenerator.previewImage != nil
	}
	@MainActor
	var animationIsBeingGeneratedNow: Bool {
		fullAnimationPreviewGenerator.imageBeingGeneratedNow
	}

	@MainActor
	var somePreviewGenerationInProgress: Bool {
		showPreview && (animationIsBeingGeneratedNow || singleFramePreviewGenerator.imageBeingGeneratedNow)
	}

	private var lastConversionSettings: GIFGenerator.Conversion?

	func onSettingsDidChange(settings: GIFGenerator.Conversion) {
		lastConversionSettings = settings
		guard showPreview else {
			return
		}

		singleFramePreviewGenerator.generatePreview(command: .init(
			whatToGenerate: .oneFrame(atTime: self.currentScrubbedTime),
			settingsAtGenerateTime: settings
		))
		fullAnimationPreviewGenerator.generatePreview(command: .init(
			whatToGenerate: .entireAnimation,
			settingsAtGenerateTime: settings
		))
	}
	private var currentScrubbedTime = 0.0
	func onScrubToNewTime(player: AVPlayer, currentTime: Double) {
		currentScrubbedTime = currentTime
		guard showPreview,
			  let lastConversionSettings else {
			return
		}
		player.rate = 0


		singleFramePreviewGenerator.generatePreview(command: .init(
			whatToGenerate: .oneFrame(atTime: currentTime),
			settingsAtGenerateTime: lastConversionSettings
		))
	}

	var showPreview: Bool {
		get {
			viewUnderTrim != nil
		}

		set {
			guard newValue != showPreview else {
				return
			}
			guard newValue else {
				viewUnderTrim = nil
				return
			}

			viewUnderTrim = previewView
			guard let lastConversionSettings else {
				return
			}
			singleFramePreviewGenerator.generatePreview(command: .init(
				whatToGenerate: .oneFrame(atTime: currentScrubbedTime),
				settingsAtGenerateTime: lastConversionSettings
			))

			fullAnimationPreviewGenerator.generatePreview(command: .init(
				whatToGenerate: .entireAnimation,
				settingsAtGenerateTime: lastConversionSettings
			))

			return
		}
	}


	private var previousRate: Float = 0
	@MainActor
	func onRateDidChange(player: AVPlayer, newRate: Float ) {
		defer {
			previousRate = newRate
		}

		guard showPreview else {
			return
		}
		if fullAnimationPreviewGenerator.previewImage == nil {
			shouldShowAnimation = false
			/**
			Avoid infinite loop: stop the player if rate is already 0.
			*/
			guard newRate != 0 else {
				return
			}
			player.rate = 0
			return
		}
		shouldShowAnimation = newRate != 0

		if newRate > 0, previousRate == 0 {
			player.seekToStart()
		}
	}
}

struct PreviewView: View {
	// swiftlint:disable:next private_swiftui_state
	@State var previewViewState: PreviewViewState
    var body: some View {
		ZStack {
			CheckerboardView()
			VStack {
				if previewViewState.shouldShowAnimation {
					ImageOrProgressView(
						image: previewViewState.fullAnimationPreviewGenerator.previewImage,
						isLoading: previewViewState.fullAnimationPreviewGenerator.imageBeingGeneratedNow
					)
				} else {
					ImageOrProgressView(
						image: previewViewState.singleFramePreviewGenerator.previewImage,
						isLoading: previewViewState.singleFramePreviewGenerator.imageBeingGeneratedNow
					)
				}
			}
		}
	}

	private struct ImageOrProgressView: View {
		var image: PreviewGenerator.PreviewImage?
		var isLoading: Bool

		var body: some View {
			ZStack {
				switch image {
				case .image(let image):
					ImageView(image: image)
						.scaledToFit()
				case .tooFewFrames:
					Text("Not enough frames for a preview.")
						.font(.title)
						.multilineTextAlignment(.center)
						.padding()

				case .none:
					Group{}
				}
				if image == nil || isLoading {
					ProgressView()
						/**
						 ProgressView won't scale with a larger frame
						 */
						.scaleEffect(7.5)
				}
			}
		}
	}
}
