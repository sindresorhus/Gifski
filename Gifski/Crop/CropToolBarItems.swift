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
	@Default(.suppressCropTooltip) private var suppressCropTooltip
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
			VStack(alignment: .leading, spacing: 10) {
				Text("Crop Tips")
					.font(.headline)
				Text("• Hold Shift to scale both sides.")
				Text("• Hold Option to resize from the center.")
				Text("• Hold both to resize from the center while keeping the aspect ratio intact.")
			}
			.padding()
			.frame(width: 250)
		}
	}
}

fileprivate struct AspectRatioPicker: View {
	var metadata: AVAsset.VideoMetadata
	@Binding var outputCropRect: CropRect

	private enum AspectRatio: Hashable {
		case preset(PickerAspectRatio)
		case custom
		case reset
		case divider
	}

	@State private var customAspectRatio: PickerAspectRatio?
	@State private var showEnterCustomAspectRatio = false

	var body: some View {
		Picker("Aspect Ratio", selection: .init(
			get: {
				let aspect = (outputCropRect.width * metadata.dimensions.width) / (outputCropRect.height * metadata.dimensions.height)

				let ratios = {
					guard let customAspectRatio else {
						return PickerAspectRatio.presets
					}
					return PickerAspectRatio.presets + [customAspectRatio]
				}()

				for preset in ratios {
					if (Double(preset.width) / Double(preset.height)).isAlmostEqual(to: aspect)  {
						return AspectRatio.preset(preset)
					}
				}
				return AspectRatio.custom
			},
			set: { (newAspectRatio: AspectRatio) in
				switch newAspectRatio {
				case .divider:
					return
				case .reset:
					outputCropRect = .initialCropRect
				case .custom:
					customAspectRatio = customAspectRatio ?? currentCropRectAspectRatio
					showEnterCustomAspectRatio = true
				case .preset(let preset):
					outputCropRect = preset.cropRect(dimensions: metadata.dimensions)
				}
			}
		)) {
			ForEach(PickerAspectRatio.presets, id: \.self) { aspectRatio in
				Text(aspectRatio.label).tag(AspectRatio.preset(aspectRatio))
			}
			Divider().tag(AspectRatio.divider)
			if let customAspectRatio,
			   !customAspectRatio.isAPreset()
			{
				Text(customAspectRatio.label).tag(AspectRatio.preset(customAspectRatio))
				Divider().tag(AspectRatio.divider)
			}
			Text("Custom").tag(AspectRatio.custom)
			Text("Reset").tag(AspectRatio.reset)
		}
		.onChange(of: customAspectRatio, initial: false) { _, newRatio in
			guard let newRatio else {
				return
			}
			outputCropRect = PickerAspectRatio(newRatio.width, newRatio.height).cropRect(dimensions: metadata.dimensions)
		}
		.popover(isPresented: $showEnterCustomAspectRatio) {
			VStack(alignment: .leading, spacing: 10) {
				HStack {
					IntTextField(
						value: .init(get: {
							customAspectRatio?.width ?? 1
						}, set: {
							guard let customAspectRatio,
								  $0 > 0 else {
								return
							}
							self.customAspectRatio = .init($0, customAspectRatio.height)
						}),
						minMax: 1...99,
						alignment: .right,
						font: .monospacedSystemFont(ofSize: 12, weight: .regular)
					)
					.frame(width: 23.0)

					Text(":")
					IntTextField(
						value: .init(get: {
							customAspectRatio?.height ?? 1
						}, set: {
							guard let customAspectRatio,
								  $0 > 0 else {
								return
							}
							self.customAspectRatio = .init(customAspectRatio.width, $0)
						}),
						minMax: 1...99,
						font: .monospacedDigitSystemFont(ofSize: 0, weight: .regular)
					)
					.frame(width: 26.0)
				}.frame(width: 90)
			}
			.padding()
			.frame(width: 90)
		}
	}
	private var currentCropRectAspectRatio: PickerAspectRatio {
		let width = Int(outputCropRect.width * metadata.dimensions.width)
		let height = Int(outputCropRect.height * metadata.dimensions.height)

		let gcdValue = greatestCommonDivisor(width, height)
		let ratioWidth = width / gcdValue
		let ratioHeight = height / gcdValue
		if ratioWidth < 100 && ratioHeight < 100 {
			return .init(ratioWidth, ratioHeight)
		}
		let aspect = Double(ratioWidth) / Double(ratioHeight)
		var bestError = Double.infinity
		var bestPair = (width: 1, height: 1)
		for denominator in 1..<100 {
			let numeratior = Int(round(aspect * Double(denominator)))
			guard numeratior > 0,
				  numeratior < 100 else {
				continue
			}
			let candidateAspect = Double(numeratior) / Double(denominator)
			let error = abs(candidateAspect - aspect)

			if error < bestError {
				bestError = error
				bestPair = (width: numeratior, height: denominator)
			}
		}
		return .init(bestPair.width, bestPair.height)
	}
}



private struct PickerAspectRatio: Hashable {
	let width: Int
	let height: Int
	init(_ width: Int, _ height: Int) {
		self.width = width
		self.height = height
	}
	var label: String {
		"\(width):\(height)"
	}

	func cropRect(dimensions: CGSize) -> CropRect {
		let newAspect = CGSize(width: width, height: height)
		let newSize = newAspect.aspectFittedSize(targetWidth: dimensions.width, targetHeight: dimensions.height)

		let cropWidth = newSize.width / dimensions.width
		let cropHeight = newSize.height / dimensions.height
		return .init(
			origin: .init(x: 0.5 - cropWidth / 2.0, y: 0.5 - cropHeight / 2.0),
			size: .init(
				x: cropWidth,
				y: cropHeight
			)
		)
	}
	static let presets: [Self] = [
		.init(16, 9),
		.init(4, 3),
		.init(1, 1),
		.init(9, 16),
		.init(3, 4)
	]

	func isAPreset() -> Bool {
		Self.presets.contains {
			$0.aspectRatio.isAlmostEqual(to: self.aspectRatio)
		}
	}
}
