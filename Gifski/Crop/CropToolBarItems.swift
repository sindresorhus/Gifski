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
	@Environment(AppState.self) private var appState
	var metadata: AVAsset.VideoMetadata
	@Binding var outputCropRect: CropRect

	var body: some View {
		if appState.isCropActive {
			AspectRatioPicker(
				metadata: metadata,
				outputCropRect: $outputCropRect
			)
		}
		Toggle(isOn: appState.isCropActiveBinding)
		{
			Label("Crop", systemImage: "crop")
		}
		.popover(isPresented: appState.binding(for: \.showCropTooltip)) {
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
			updateCropRect(for: newRatio)
		}
		.popover(isPresented: $showEnterCustomAspectRatio) {
			CustomAspectRatioView(customAspectRatio: $customAspectRatio)
		}
	}

	private var selectionText: String {
		PickerAspectRatio.selectionText(for: aspect, customAspectRatio: customAspectRatio)
	}

	private var presetSection: some View {
		Section(header: Text("Presets")) {
			ForEach(PickerAspectRatio.presets, id: \.self) { aspectRatio in
				AspectToggle(
					aspectRatio: aspectRatio,
					outputCropRect: $outputCropRect,
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
					currentAspect: aspect,
					dimensions: metadata.dimensions
				)
			}
		}
	}

	private var optionsSection: some View {
		Section(header: Text("Options")) {
			Toggle(isOn: Binding(
				get: { false },
				set: { _ in handleCustomAspectToggle() }
			)) {
				Text("Custom")
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

	private func handleCustomAspectToggle() {
		customAspectRatio = customAspectRatio ?? PickerAspectRatio.closestAspectRatio(
			for: outputCropRect.unnormalize(forDimensions: metadata.dimensions).size,
			within: aspectRatioNumberRange
		)
		showEnterCustomAspectRatio = true
	}

	private func resetAspectRatio() {
		customAspectRatio = nil
		outputCropRect = .initialCropRect
	}

	private func updateCropRect(for newRatio: PickerAspectRatio?) {
		guard let newRatio else {
			return
		}
		outputCropRect = PickerAspectRatio(newRatio.width, newRatio.height)
			.cropRect(dimensions: metadata.dimensions)
	}
}

private struct AspectToggle: View {
	var aspectRatio: PickerAspectRatio
	@Binding var outputCropRect: CropRect
	var currentAspect: Double
	var dimensions: CGSize

	var body: some View {
		Toggle(isOn: Binding(
			get: { aspectRatio.aspectRatio.isAlmostEqual(to: currentAspect) },
			set: { _ in outputCropRect = aspectRatio.cropRect(dimensions: dimensions) }
		)) {
			Text(aspectRatio.description)
		}
	}
}

private struct CustomAspectRatioView: View  {
	@Binding var customAspectRatio: PickerAspectRatio?

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				CustomAspectField(customAspectRatio: $customAspectRatio, side: \.width)
				Text(":")
				CustomAspectField(customAspectRatio: $customAspectRatio, side: \.height)
			}.frame(width: 90)
		}
		.padding()
		.frame(width: 90)
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
			alignment: .right,
			font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
		)
		.frame(width: 26.0)
	}
}


struct PickerAspectRatio: Hashable, CustomStringConvertible  {
	var width: Int
	var height: Int

	init(_ width: Int, _ height: Int) {
		self.width = width
		self.height = height
	}
	var description: String {
		"\(width):\(height)"
	}

	var aspectRatio: Double {
		Double(width) / Double(height)
	}

	func cropRect(dimensions: CGSize) -> CropRect {
		CropRect.from(aspectWidth: Double(width), aspectHeight: Double(height), forDimensions: dimensions)
	}
	static let presets: [Self] = [
		.init(16, 9),
		.init(4, 3),
		.init(1, 1),
		.init(9, 16),
		.init(3, 4)
	]
}

extension PickerAspectRatio {
	func matchesPreset() -> Bool {
		Self.presets.contains { $0.isCloseTo(self.aspectRatio) }
	}
	func isCloseTo(_ aspect: Double, tolerance: Double = 0.01) -> Bool {
		abs(self.aspectRatio - aspect) < tolerance
	}

	static func selectionText(for aspect: Double, customAspectRatio: PickerAspectRatio?) -> String {
		let ratios = presets + (customAspectRatio.map { [$0] } ?? [])
		return ratios.first { $0.aspectRatio.isAlmostEqual(to: aspect) }?.description ?? "Custom"
	}
	/**
	Calculates the closest current aspect ratio of the cropRec with width and height less than 100. First, it tries to calculate the greatest common divisor (GCD) of the width and height to simplify the ratio. If the the width and height of the ratio are both less than 100, it uses that as the aspect ratio. Otherwise, it approximates the aspect ratio by finding the closest fraction with a denominator less than 100 that matches the current aspect ratio as closely as possible.
	*/
	static func closestAspectRatio(for size: CGSize, within range: ClosedRange<Int>) -> Self {
		let (intWidth, intHeight) = size.integerAspectRatio()
		if range.contains(intWidth), range.contains(intHeight) {
			return .init(intWidth, intHeight)
		}
		return approximateAspectRatio(for: size, within: range)
	}

	private static func approximateAspectRatio(for size: CGSize, within range: ClosedRange<Int>) -> Self {
		let aspect = size.width / size.height
		let bestPairMap	 = range
			.flatMap { denominator in
				let numerator = Int(round(aspect * Double(denominator)))
				return range.contains(numerator) ? [(numerator, denominator)] : []
			}
		let bestPair = bestPairMap.min { abs(Double($0.0) / Double($0.1) - aspect) < abs(Double($1.0) / Double($1.1) - aspect) }
		?? (1, 1)

		return .init(bestPair.0, bestPair.1)
	}
}
