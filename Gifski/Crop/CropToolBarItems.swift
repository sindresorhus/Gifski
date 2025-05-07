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

fileprivate enum CustomFieldType {
	case pixel
	case aspect
}

fileprivate struct AspectRatioPicker: View {
	var metadata: AVAsset.VideoMetadata
	@Binding var outputCropRect: CropRect

	@State private var showEnterCustomAspectRatio = false
	@State private var customAspectRatio: PickerAspectRatio?
	@State private var customPixelSize: CGSize = .zero
	@State private var modifiedCustomField: CustomFieldType?

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
		.staticPopover(isPresented: $showEnterCustomAspectRatio) {
			CustomAspectRatioView(
				cropRect: $outputCropRect,
				customAspectRatio: $customAspectRatio,
				customPixelSize: $customPixelSize,
				modifiedCustomField: $modifiedCustomField,
				dimensions: metadata.dimensions
			)
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
		let cropSizeRightNow = outputCropRect.unnormalize(forDimensions: metadata.dimensions).size
		customAspectRatio = PickerAspectRatio.closestAspectRatio(
			for: cropSizeRightNow,
			within: aspectRatioNumberRange
		)
		customPixelSize = cropSizeRightNow
		modifiedCustomField = nil
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
			Text(aspectRatio.description)
		}
	}
}

private struct CustomAspectRatioView: View  {
	@Binding var cropRect: CropRect
	@Binding var customAspectRatio: PickerAspectRatio?
	@Binding var customPixelSize: CGSize
	@Binding var modifiedCustomField: CustomFieldType?
	var dimensions: CGSize

	var body: some View {
		VStack(spacing: 10) {
			HStack {
				CustomAspectField(customAspectRatio: $customAspectRatio, modifiedCustomField: $modifiedCustomField, side: \.width)
				Text(":")
				CustomAspectField(customAspectRatio: $customAspectRatio, modifiedCustomField: $modifiedCustomField, side: \.height)
			}.frame(width: 90).opacity(modifiedCustomField == .pixel ? 0.5 : 1.0)
			HStack {
				CustomPixelField(customPixelSize: $customPixelSize, cropRect: $cropRect, modifiedCustomField: $modifiedCustomField, dimensions: dimensions, side: \.width)
				Text("x")
				CustomPixelField(customPixelSize: $customPixelSize, cropRect: $cropRect, modifiedCustomField: $modifiedCustomField, dimensions: dimensions, side: \.height)
			}.frame(width: 135).opacity(modifiedCustomField == .aspect ? 0.5 : 1.0)
		}
		.padding()
		.frame(width: 135)
	}
}

private let fieldFont: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

private struct CustomPixelField: View {
	@Binding var customPixelSize: CGSize
	@Binding var cropRect: CropRect
	@Binding var modifiedCustomField: CustomFieldType?

	var dimensions: CGSize
	// swiftlint:disable:next no_cgfloat
	let side: WritableKeyPath<CGSize, CGFloat>
	@State private var showWarning = false

	static let minValue = 100
	var body: some View {
		IntTextField(
			value: .init(get: {
				value
			}, set: {
				let newValue = $0.clamped(to: Self.minValue...Int(dimensions[keyPath: side]))
				var newSize = cropRect.size
				newSize[keyPath: unitSizeSide] = Double(newValue) / dimensions[keyPath: side]
				cropRect = cropRect.centeredRectWith(size: newSize, minSize: CropRect.minSize(videoSize: dimensions))

				if value != $0 {
					modifiedCustomField = .pixel
				}
				customPixelSize[keyPath: side] = Double($0)
				showWarning = $0 < Self.minValue
			}),
			minMax: Self.minValue...Int(dimensions[keyPath: side]),
			alignment: isWidth ? .right : .left,
			font: fieldFont
		)
		.frame(width: 42.0)
		.popover2(isPresented: $showWarning) {
			VStack {
				Text("Value is too small!")
				Text("\(value) < \(Self.minValue)")
			}
			.padding()
		}
	}

	var value: Int {
		Int(customPixelSize[keyPath: side].rounded())
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
	@Binding var modifiedCustomField: CustomFieldType?
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
				if customAspectRatioCopy[keyPath: side] != $0 {
					modifiedCustomField = .aspect
				}
				customAspectRatioCopy[keyPath: side] = $0
				self.customAspectRatio = customAspectRatioCopy
			}),
			minMax: aspectRatioNumberRange,
			alignment: side == \.width ? .right : .left,
			font: fieldFont
		)
		.frame(width: 26.0)
	}
}
