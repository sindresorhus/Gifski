//
//  CropToolBarItems.swift
//  Gifski
//
//  Created by Michael Mulet on 4/28/25.
//

import Foundation
import SwiftUI
import AVFoundation

struct CropToolbarItems: View {
	@Binding var isCropActive: Bool
	var metadata: AVAsset.VideoMetadata
	@Binding var outputCropRect: CropRect
	@State private var showCropTooltip = false

	var body: some View {
		if isCropActive {
			AspectRatioPicker(
				metadata: metadata,
				outputCropRect: $outputCropRect
			)
		}
		Toggle(isOn: $isCropActive)
		{
			Label("Crop", systemImage: "crop")
		}
		.onChange(of: isCropActive) {
			guard isCropActive else {
				return
			}
			SSApp.runOnce(identifier: "showCropTooltip") {
				self.showCropTooltip = true
			}
		}
		.popover(isPresented: $showCropTooltip) {
			TipsView(title: "Crop Tips", tips: Self.tips)
		}
	}
	static let tips = [
		"• Hold Shift to scale both sides.",
		"• Hold Option to resize from the center.",
		"• Hold both to resize from the center while keeping the aspect ratio intact."
	]
}

/**
The range of valid numbers for the aspect ratio.
*/
fileprivate let aspectRatioNumberRange = 1...99
fileprivate struct AspectRatioPicker: View {
	var metadata: AVAsset.VideoMetadata
	@Binding var outputCropRect: CropRect

	@State private var customAspectRatio: PickerAspectRatio?
	@State private var showEnterCustomAspectRatio = false

	var body: some View {
		Menu(selectionText) {
			presetSection
			customSection
			optionsSection
		}
		.onChange(of: customAspectRatio) { _, newRatio in
			guard let newRatio else {
				return
			}
			outputCropRect = outputCropRect.withAspectRatio(for: newRatio, forDimensions: metadata.dimensions)
		}
		.popover(isPresented: $showEnterCustomAspectRatio) {
			CustomAspectRatioView(cropRect: $outputCropRect, customAspectRatio: $customAspectRatio, dimensions: metadata.dimensions)
		}
	}

	private var selectionText: String {
		PickerAspectRatio.selectionText(for: aspect, customAspectRatio: customAspectRatio, videoDimensions: metadata.dimensions, cropRect: outputCropRect)
	}

	private var presetSection: some View {
		Section(header: Text("Presets")) {
			ForEach(PickerAspectRatio.presets, id: \.self) { aspectRatio in
				AspectToggle(
					aspectRatio: aspectRatio,
					outputCropRect: $outputCropRect,
					customAspectRatio: $customAspectRatio,
					currentAspect: aspect,
					dimensions: metadata.dimensions
				)
			}
		}
	}
	@ViewBuilder
	private var customSection: some View {
		if let customAspectRatio, !customAspectRatio.matchesPreset() {
			Section(header: Text("Custom")) {
				AspectToggle(
					aspectRatio: customAspectRatio,
					outputCropRect: $outputCropRect,
					customAspectRatio: $customAspectRatio,
					currentAspect: aspect,
					dimensions: metadata.dimensions
				)
			}
		}
	}

	private var optionsSection: some View {
		Section(header: Text("Options")) {
			Button("Custom") {
				handleCustomAspectButton()
			}
			Button("Reset") {
				resetAspectRatio()
			}
		}
	}

	private var aspect: Double {
		let cropRectInPixels = outputCropRect.unnormalize(forDimensions: metadata.dimensions)
		return cropRectInPixels.width / cropRectInPixels.height
	}

	private func handleCustomAspectButton() {
		customAspectRatio = PickerAspectRatio.closestAspectRatio(
			for: outputCropRect.unnormalize(forDimensions: metadata.dimensions).size,
			within: aspectRatioNumberRange
		)
		showEnterCustomAspectRatio = true
	}

	private func resetAspectRatio() {
		customAspectRatio = nil
		outputCropRect = .initialCropRect
	}
}

private struct AspectToggle: View {
	var aspectRatio: PickerAspectRatio
	@Binding var outputCropRect: CropRect
	@Binding var customAspectRatio: PickerAspectRatio?
	var currentAspect: Double
	var dimensions: CGSize

	var body: some View {
		Toggle(isOn: Binding(
			get: { aspectRatio.aspectRatio.isAlmostEqual(to: currentAspect) },
			set: { _ in
				outputCropRect = outputCropRect.withAspectRatio(for: aspectRatio, forDimensions: dimensions)
			}
		)) {
			Text(aspectRatio.description(forVideoDimensions: dimensions, cropRect: outputCropRect))
		}
	}
}

private struct CustomAspectRatioView: View  {
	@Binding var cropRect: CropRect
	@Binding var customAspectRatio: PickerAspectRatio?
	var dimensions: CGSize

	var body: some View {
		VStack(spacing: 10) {
			HStack {
				CustomAspectField(customAspectRatio: $customAspectRatio, side: \.width)
				Text(":")
				CustomAspectField(customAspectRatio: $customAspectRatio, side: \.height)
			}.frame(width: 90)
			HStack {
				CustomPixelField(cropRect: $cropRect, dimensions: dimensions, side: \.width)
				Text("x")
				CustomPixelField(cropRect: $cropRect, dimensions: dimensions, side: \.height)
			}.frame(width: 135)
		}
		.padding()
		.frame(width: 135)
	}
}


private struct CustomPixelField: View {
	@Binding var cropRect: CropRect
	var dimensions: CGSize
	// swiftlint:disable:next no_cgfloat
	let side: WritableKeyPath<CGSize, CGFloat>
	var body: some View {
		IntTextField(
			value: .init(get: {
				Int(cropRect.unnormalize(forDimensions: dimensions).size[keyPath: side])
			}, set: {
				guard minMax.contains($0)  else {
					return
				}
				var newSize = cropRect.size
				newSize[keyPath: unitSizeSide] = Double($0) / dimensions[keyPath: side]
				cropRect = cropRect.centeredRectWith(size: newSize)
			}),
			minMax: minMax,
			alignment: isWidth ? .right : .left,
			font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
		)
		.frame(width: 42.0)
	}
	var minMax: ClosedRange<Int> {
		101...Int(dimensions[keyPath: side])
	}
	var isWidth: Bool {
		side == \.width
	}
	var unitSizeSide: WritableKeyPath<UnitSize, Double> {
		isWidth ? \.width : \.height
	}
}

private struct CustomAspectField: View {
	@Binding var customAspectRatio: PickerAspectRatio?
	let side: WritableKeyPath<PickerAspectRatio, Int>

	var body: some View {
		IntTextField(
			value: .init(get: {
				customAspectRatio?[keyPath: side] ?? 1
			}, set: {
				guard var customAspectRatioCopy = customAspectRatio,
					  $0 > 0 else {
					return
				}
				customAspectRatioCopy[keyPath: side] = $0
				self.customAspectRatio = customAspectRatioCopy
			}),
			minMax: aspectRatioNumberRange,
			alignment: side == \.width ? .right : .left,
			font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
		)
		.frame(width: 26.0)
	}
}
