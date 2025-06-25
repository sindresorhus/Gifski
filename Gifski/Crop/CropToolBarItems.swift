import SwiftUI
import AVFoundation

struct CropToolbarItems: View {
	@State private var showCropTooltip = false

	@Binding var isCropActive: Bool
	let metadata: AVAsset.VideoMetadata
	@Binding var outputCropRect: CropRect
	@FocusState private var isCropToggleFocused: Bool

	var body: some View {
		HStack {
			if isCropActive {
				AspectRatioPicker(
					metadata: metadata,
					outputCropRect: $outputCropRect
				)
			}
			Toggle("Crop", systemImage: "crop", isOn: $isCropActive)
				.focused($isCropToggleFocused)
				.onChange(of: isCropActive) {
					isCropToggleFocused = true
					guard isCropActive else {
						return
					}
					SSApp.runOnce(identifier: "showCropTooltip") {
						showCropTooltip = true
					}
				}
				.popover(isPresented: $showCropTooltip) {
					TipsView(title: "Crop Tips", tips: Self.tips)
				}
		}
	}

	private static let tips = [
		"• Hold Shift to scale both sides.",
		"• Hold Option to resize from the center.",
		"• Hold both to keep aspect ratio and resize from center."
	]
}

private enum CustomFieldType {
	case pixel
	case aspect
}

private struct AspectRatioPicker: View {
	@State private var showEnterCustomAspectRatio = false
	@State private var customAspectRatio: PickerAspectRatio?
	@State private var customPixelSize = CGSize.zero
	@State private var modifiedCustomField: CustomFieldType?

	let metadata: AVAsset.VideoMetadata
	@Binding var outputCropRect: CropRect

	var body: some View {
		Menu(selectionText) {
			presetSection
			customSection
			otherSections
		}
		.onChange(of: customAspectRatio) {
			guard let customAspectRatio else {
				return
			}

			outputCropRect = outputCropRect.withAspectRatio(
				for: customAspectRatio,
				forDimensions: metadata.dimensions
			)

			// Change the `customAspectRatio` to reflect the bounded crop rect (as in it is not too small on one side), but debounce it to let the user enter intermediate invalid values.
			Debouncer.debounce(delay: .seconds(2)) {
				let cropSizeRightNow = outputCropRect.unnormalize(forDimensions: metadata.dimensions).size

				let newRatio = PickerAspectRatio.closestAspectRatio(
					for: cropSizeRightNow,
					within: CropRect.defaultAspectRatioBounds
				)

				guard newRatio.aspectRatio != self.customAspectRatio?.aspectRatio else {
					// Prevent simplification (like `25:5` -> `5:1`), only assign if the aspect ratio is new.
					return
				}

				self.customAspectRatio = newRatio
			}
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
		Section("Presets") {
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
		if
			let customAspectRatio,
			!customAspectRatio.matchesPreset()
		{
			Section("Custom") {
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

	@ViewBuilder
	private var otherSections: some View {
		Section {
			Button("Custom") {
				handleCustomAspectButton()
			}
		}
		Section {
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
			within: CropRect.defaultAspectRatioBounds
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
		Toggle(
			aspectRatio.description,
			isOn: .init(
				get: {
					aspectRatio.aspectRatio.isAlmostEqual(to: currentAspect)
				},
				set: { _ in
					outputCropRect = outputCropRect.withAspectRatio(for: aspectRatio, forDimensions: dimensions)
				}
			)
		)
	}
}

private struct CustomAspectRatioView: View {
	@Binding var cropRect: CropRect
	@Binding var customAspectRatio: PickerAspectRatio?
	@Binding var customPixelSize: CGSize
	@Binding var modifiedCustomField: CustomFieldType?
	var dimensions: CGSize

	var body: some View {
		VStack(spacing: 10) {
			HStack(spacing: 4) {
				CustomAspectField(
					customAspectRatio: $customAspectRatio,
					modifiedCustomField: $modifiedCustomField,
					side: \.width
				)
				Text(":")
					.foregroundStyle(.secondary)
				CustomAspectField(
					customAspectRatio: $customAspectRatio,
					modifiedCustomField: $modifiedCustomField,
					side: \.height
				)
			}
			.frame(width: 90)
			.opacity(modifiedCustomField == .pixel ? 0.7 : 1)
			HStack(spacing: 4) {
				CustomPixelField(
					customPixelSize: $customPixelSize,
					cropRect: $cropRect,
					modifiedCustomField: $modifiedCustomField,
					dimensions: dimensions,
					side: \.width
				)
				Text("x")
					.foregroundStyle(.secondary)
				CustomPixelField(
					customPixelSize: $customPixelSize,
					cropRect: $cropRect,
					modifiedCustomField: $modifiedCustomField,
					dimensions: dimensions,
					side: \.height
				)
			}
			.opacity(modifiedCustomField == .aspect ? 0.7 : 1)
		}
		.padding()
		.frame(width: 135)
	}
}

private struct CustomPixelField: View {
	@Binding var customPixelSize: CGSize
	@Binding var cropRect: CropRect
	@Binding var modifiedCustomField: CustomFieldType?

	var dimensions: CGSize
	// swiftlint:disable:next no_cgfloat
	let side: WritableKeyPath<CGSize, CGFloat>
	@State private var showWarning = false
	@State private var warningCount = 0

	var body: some View {
		IntTextField(
			value: .init(
				get: {
					value
				},
				set: {
					guard minMax.contains($0) else {
						return
					}

					var newSize = cropRect.size
					newSize[keyPath: unitSizeSide] = Double($0) / dimensions[keyPath: side]
					cropRect = cropRect.changeSize(size: newSize, minSize: CropRect.minSize(videoSize: dimensions))

					if value != $0 {
						modifiedCustomField = .pixel
					}

					customPixelSize[keyPath: side] = Double($0)
					showWarning = false
				}
			),
			minMax: minMax,
			alignment: isWidth ? .right : .left,
			font: .fieldFont,
			//swiftlint:disable:next trailing_closure
			onInvalid: { invalidValue in
				customPixelSize[keyPath: side] = Double(invalidValue.clamped(to: minMax))
				warningCount += 1
				showWarning = true
			}
		)
		.onChange(of: warningCount) {} // Noop. Having the `warningCount` in the view hierarchy causes SwiftUI to refresh the `IntTextField` whenever an invalid value is entered even if we have already set the pixel size to `Self.minValue`. Can't use `.id()` modifier because it will close the popover.
		.frame(width: 42.0)
		.popover2(isPresented: $showWarning) {
			VStack {
				Text("Value must be in the range \(minMax.lowerBound) to \(minMax.upperBound)")
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

	var minMax: ClosedRange<Int> {
		Int(CropRect.minRectWidthHeight)...Int(dimensions[keyPath: side])
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
			value: .init(
				get: {
					customAspectRatio?[keyPath: side] ?? 1
				},
				set: {
					guard
						var customAspectRatioCopy = customAspectRatio,
						$0 > 0
					else {
						return
					}

					if customAspectRatioCopy[keyPath: side] != $0 {
						modifiedCustomField = .aspect
					}

					customAspectRatioCopy[keyPath: side] = $0.clamped(to: minMax)
					customAspectRatio = customAspectRatioCopy
				}
			),
			minMax: minMax,
			alignment: side == \.width ? .right : .left,
			font: .fieldFont
		)
		.frame(width: 26.0)
	}

	var minMax: ClosedRange<Int> {
		CropRect.defaultAspectRatioBounds
	}

	var isWidth: Bool {
		side == \.width
	}

	var unitSizeSide: WritableKeyPath<UnitSize, Double> {
		isWidth ? \.width : \.height
	}
}

private struct TipsView: View {
	let title: String
	let tips: [String]

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(title)
				.font(.headline)
			ForEach(tips, id: \.self) { tip in
				Text(tip)
			}
		}
		.padding()
		.fixedSize()
	}
}

extension NSFont {
	fileprivate static var fieldFont: NSFont {
		monospacedDigitSystemFont(ofSize: 12, weight: .regular)
	}
}
