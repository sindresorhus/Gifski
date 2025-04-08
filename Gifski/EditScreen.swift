import SwiftUI
import AVFoundation

struct EditScreen: View {
	@Environment(AppState.self) private var appState
	@Default(.outputQuality) private var outputQuality
	@Default(.bounceGIF) private var bounceGIF
	@Default(.outputFPS) private var frameRate
	@Default(.loopGIF) private var loopGIF
	@Default(.suppressKeyframeWarning) private var suppressKeyframeWarning
	@Default(.outputCrop) private var outputCrop
	@Default(.outputCropRect) private var outputCropRect
	@State private var url: URL
	@State private var asset: AVAsset
	@State private var modifiedAsset: AVAsset
	@State private var metadata: AVAsset.VideoMetadata
	@State private var estimatedFileSizeModel = EstimatedFileSizeModel()
	@State private var timeRange: ClosedRange<Double>?
	@State private var loopCount = 0
	@State private var isKeyframeRateChecked = false
	@State private var isReversePlaybackWarningPresented = false
	@State private var resizableDimensions = Dimensions.percent(1, originalSize: .init(widthHeight: 100))
	@State private var shouldShow = false

	init(
		url: URL,
		asset: AVAsset,
		metadata: AVAsset.VideoMetadata
	) {
		self._url = .init(wrappedValue: url)
		self._asset = .init(wrappedValue: asset)
		self._modifiedAsset = .init(wrappedValue: asset)
		self._metadata = .init(wrappedValue: metadata)
	}

	var body: some View {
		VStack {
			// TODO: Move the trimmer outside the video view.
				TrimmingAVPlayer(
					asset: modifiedAsset,
					loopPlayback: loopGIF,
					bouncePlayback: bounceGIF,
					showCropRectUnderTrim: outputCrop ? outputCropRect : nil
				) { timeRange in
					DispatchQueue.main.async {
						self.timeRange = timeRange
					}
				}
			controls
			bottomBar
		}
		.background(.ultraThickMaterial)
		.navigationTitle(url.lastPathComponent)
		.navigationDocument(url)
		.onReceive(Defaults.publisher(.outputSpeed, options: []).removeDuplicates().debounce(for: .seconds(0.4), scheduler: DispatchQueue.main)) { _ in
			Task {
				await setSpeed()
			}
		}
		// We cannot use `Defaults.publisher(.outputSpeed, options: [])` without the `options` as it causes some weird glitches.
		.task {
			await setSpeed()
		}
		.onChange(of: outputQuality, initial: true) {
			estimatedFileSizeModel.duration = metadata.duration
			estimatedFileSizeModel.updateEstimate()
		}
		// TODO: Make these a single call when tuples are equatable.
		.onChange(of: resizableDimensions) {
			estimatedFileSizeModel.updateEstimate()
		}
		.onChange(of: timeRange) {
			estimatedFileSizeModel.updateEstimate()
		}
		.onChange(of: bounceGIF) {
			estimatedFileSizeModel.updateEstimate()
		}
		.onChange(of: frameRate) {
			estimatedFileSizeModel.updateEstimate()
		}
		.onChange(of: bounceGIF) {
			guard bounceGIF else {
				return
			}

			showKeyframeRateWarningIfNeeded()
		}
		.alert2(
			"Reverse Playback Preview Limitation",
			message: "Reverse playback may stutter when the video has a low keyframe rate. The GIF will not have the same stutter.",
			isPresented: $isReversePlaybackWarningPresented
		)
		.dialogSuppressionToggle(isSuppressed: $suppressKeyframeWarning)
		.opacity(shouldShow ? 1 : 0)
		.onAppear {
			setUp()
		}
		.task {
			try? await Task.sleep(for: .seconds(0.3))

			withAnimation {
				shouldShow = true
			}
		}
	}

	private func setSpeed() async {
		do {
			// We could have set the `rate` of the player instead of modifying the asset, but it's just easier to modify the asset as then it matches what we want to generate. Otherwise, we would have to translate trimming ranges to the correct speed, etc.
			modifiedAsset = try await asset.firstVideoTrack?.extractToNewAssetAndChangeSpeed(to: Defaults[.outputSpeed]) ?? modifiedAsset
			estimatedFileSizeModel.updateEstimate()
		} catch {
			appState.error = error
		}
	}

	private func setUp() {
		estimatedFileSizeModel.getConversionSettings = { conversionSettings }
	}

	private var controls: some View {
		HStack(spacing: 0) {
			Form {
				DimensionsSetting(
					asset: modifiedAsset,
					metadata: metadata,
					bounceGIF: bounceGIF,
					videoDimensions: metadata.dimensions,
					resizableDimensions: $resizableDimensions,
					outputCrop: $outputCrop
				)
				SpeedSetting()
					.padding(.bottom, 6) // Makes the forms have equal height.
			}
			.padding(.horizontal, -8) // Form comes with some default padding, which we don't want.
			.fillFrame()
			.containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)
			.padding(.trailing, -8)
			Form {
				FrameRateSetting(videoFrameRate: metadata.frameRate)
				QualitySetting()
				LoopSetting(loopCount: $loopCount)
			}
			.padding(.horizontal, -8)
			.fillFrame()
			.containerRelativeFrame(.horizontal, count: 2, span: 1, spacing: 0)
		}
		.padding(-12)
		.formStyle(.grouped)
		.scrollContentBackground(.hidden)
		.scrollDisabled(true)
		.fixedSize()
	}

	private var bottomBar: some View {
		HStack {
			Spacer()
			Button("Convert") {
				appState.navigationPath.append(.conversion(conversionSettings))
			}
			.keyboardShortcut(.defaultAction)
			.padding(.top, -1) // Makes the bar have equal spacing on top and bottom.
		}
		.overlay {
			EstimatedFileSizeView(model: estimatedFileSizeModel)
		}
		.padding()
		.padding(.top, -16)
	}

	private var conversionSettings: GIFGenerator.Conversion {
		print("resizableDimensions:", resizableDimensions.pixels, resizableDimensions.percent)
		return .init(
			asset: modifiedAsset,
			sourceURL: url,
			timeRange: timeRange,
			quality: outputQuality,
			dimensions: resizableDimensions.pixels.toInt,
			frameRate: frameRate,
			loop: {
				guard loopGIF else {
					return loopCount == 0 ? .never : .count(loopCount)
				}

				return .forever
			}(),
			bounce: bounceGIF,
			crop: outputCrop ? outputCropRect : nil
		)
	}

	private func showKeyframeRateWarningIfNeeded(maximumKeyframeInterval: Double = 30) {
		guard
			!isKeyframeRateChecked,
			!Defaults[.suppressKeyframeWarning]
		else {
			return
		}

		isKeyframeRateChecked = true

		Task.detached(priority: .utility) {
			do {
				guard
					let keyframeInfo = try await modifiedAsset.firstVideoTrack?.getKeyframeInfo(),
					keyframeInfo.keyframeInterval > maximumKeyframeInterval
				else {
					return
				}

				print("Low keyframe interval \(keyframeInfo.keyframeInterval)")

				await MainActor.run {
					isReversePlaybackWarningPresented = true
				}
			} catch {
				await MainActor.run {
					appState.error = error
				}
			}
		}
	}
}

enum PredefinedSizeItem: Hashable {
	case custom
	case spacer
	case dimensions(Dimensions)

	var resizableDimensions: Dimensions? {
		switch self {
		case .dimensions(let dimensions):
			dimensions
		default:
			nil
		}
	}
}

private struct DimensionsSetting: View {
	@Environment(AppState.self) private var appState
	var asset: AVAsset
	var metadata: AVAsset.VideoMetadata
	var bounceGIF: Bool
	@State private var predefinedSizes = [PredefinedSizeItem]()
	@State private var selectedPredefinedSize: PredefinedSizeItem?
	@State private var dimensionsType = DimensionsType.pixels
	@State private var width = 0
	@State private var height = 0
	@State private var percent = 0
	@State private var isArrowKeyTipPresented = false

	@State private var shouldCrop = false

	let videoDimensions: CGSize
	@Binding var resizableDimensions: Dimensions // TODO: Rename.
	@Binding var outputCrop: Bool


	var body: some View {
		VStack(spacing: 16) {
			Picker("Dimensions", selection: $selectedPredefinedSize) {
				ForEach(predefinedSizes, id: \.self) { size in
					switch size {
					case .custom:
						if selectedPredefinedSize == .custom {
							let string = switch dimensionsType {
							case .pixels:
								// TODO: Make this a property on `resizableDimensions`.
								String(format: "%.0f%%", resizableDimensions.percent * 100)
							case .percent:
								resizableDimensions.pixels.formatted
							}
							Text("Custom — \(string)")
								.tag(size as PredefinedSizeItem?)
						}
					case .spacer:
						Divider()
							.tag(UUID())
					case .dimensions(let dimensions):
						Text("\(dimensions.description)")
							.tag(size as PredefinedSizeItem?)
					}
				}
			}
			.onChange(of: selectedPredefinedSize) {
				updateDimensionsBasedOnSelection(selectedPredefinedSize)
			}
			HStack {
				Spacer()
				HStack {
					switch dimensionsType {
					case .pixels:
						let textFieldWidth = 42.0
						HStack(spacing: 4) {
							LabeledContent("Width") {
								IntTextField(
									value: $width,
									minMax: resizableDimensions.widthMinMax.toInt,
									onBlur: { _ in // swiftlint:disable:this trailing_closure
										DispatchQueue.main.async {
											applyWidth()
										}
									}
								)
								.frame(width: textFieldWidth)
								.onChange(of: width) {
									applyWidth()
								}
							}
							// TODO: Use TipKit when targeting macOS 15.
							.popover(isPresented: $isArrowKeyTipPresented) {
								Text("Press the arrow up/down keys to change the value by 1.\nHold the Option key meanwhile to change it by 10.")
									.padding()
									.padding(.vertical, 4)
									.onTapGesture {
										isArrowKeyTipPresented = false
									}
									.accessibilityAddTraits(.isButton)
							}
							Text("×")
							LabeledContent("Height") {
								IntTextField(
									value: $height,
									minMax: resizableDimensions.heightMinMax.toInt,
									onBlur: { _ in // swiftlint:disable:this trailing_closure
										DispatchQueue.main.async {
											applyHeight()
										}
									}
								)
								.frame(width: textFieldWidth)
								.onChange(of: height) {
									applyHeight()
								}
							}
						}
					case .percent:
						LabeledContent("Percent") {
							IntTextField(
								value: $percent,
								minMax: resizableDimensions.percentMinMax.toInt,
								onBlur: { _ in // swiftlint:disable:this trailing_closure
									DispatchQueue.main.async { // Ensures it uses updated values.
										applyPercent()
									}
								}
							)
							.frame(width: 32)
							.onChange(of: percent) {
								applyPercent()
							}
						}
					}
				}
				.padding(.trailing, -8)
				Picker("Dimension type", selection: $dimensionsType) {
					ForEach(DimensionsType.allCases, id: \.self) {
						Text($0.rawValue)
					}
				}
				.onChange(of: dimensionsType) {
					DispatchQueue.main.async { // Fixes an issue where if you do 100%, then 99%, and then try to switch to "pixel" type, it doesn't switch.
						updateTextFieldsForCurrentDimensions()
					}
				}
			}
			.fixedSize()
			.fillFrame(.horizontal, alignment: .trailing)
			.labelsHidden()
			HStack {
				Spacer()
				Toggle("Crop", isOn: $outputCrop)
				Button("Edit Crop") {
					appState.navigationPath.append(
						.editCrop(
							asset,
							metadata,
							bounceGIF
						)
					)
				}
			}
		}
		.onAppear {
			print("EDIT SCREEN - onappear")
			setUpDimensions()
			updateTextFieldsForCurrentDimensions()
			showArrowKeyTipIfNeeded()
		}
	}

	private func setUpDimensions() {
		let dimensions = Dimensions.pixels(videoDimensions, originalSize: videoDimensions)

		resizableDimensions = dimensions

		var pixelCommonSizes: [Double] = [
			960,
			800,
			640,
			500,
			480,
			320,
			256,
			200,
			160,
			128,
			80,
			64
		]

		if !pixelCommonSizes.contains(dimensions.pixels.width) {
			pixelCommonSizes.append(dimensions.pixels.width)
			pixelCommonSizes.sort(by: >)
		}

		let pixelDimensions = pixelCommonSizes.map { width in
			let ratio = width / dimensions.pixels.width
			let height = dimensions.pixels.height * ratio
			return CGSize(width: width, height: height).rounded()
		}
		.filter { $0.width <= videoDimensions.width && $0.height <= videoDimensions.height }

		let predefinedPixelDimensions = pixelDimensions
			// TODO
//			.filter { resizableDimensions.validate(newSize: $0) }
			.map { Dimensions.pixels($0, originalSize: videoDimensions) }

		let percentCommonSizes: [Double] = [
			100,
			50,
			33,
			25,
			20
		]

		let predefinedPercentDimensions = percentCommonSizes.map {
			Dimensions.percent($0 / 100, originalSize: videoDimensions)
		}

		predefinedSizes = [.custom]
		predefinedSizes.append(.spacer)
		predefinedSizes.append(contentsOf: predefinedPixelDimensions.map { .dimensions($0) })
		predefinedSizes.append(.spacer)
		predefinedSizes.append(contentsOf: predefinedPercentDimensions.map { .dimensions($0) })

		selectPredefinedSizeBasedOnCurrentDimensions()
	}

	private func updateDimensionsBasedOnSelection(_ selectedSize: PredefinedSizeItem?) {
		guard let selectedSize else {
			return
		}

		switch selectedSize {
		case .custom, .spacer:
			break
		case .dimensions(let dimensions):
			dimensionsType = dimensions.isPercent ? .percent : .pixels
			resizableDimensions = dimensions
		}

		updateTextFieldsForCurrentDimensions()
	}

	private func applyWidth() {
		print("widthMinMax", resizableDimensions.widthMinMax)
		resizableDimensions = resizableDimensions.aspectResized(usingWidth: width.toDouble)
		height = resizableDimensions.pixels.height.toDouble.clamped(to: resizableDimensions.heightMinMax).toIntAndClampingIfNeeded
		print("widthMinMax2", resizableDimensions.widthMinMax)
	}

	private func applyHeight() {
		resizableDimensions = resizableDimensions.aspectResized(usingHeight: height.toDouble)
		width = resizableDimensions.pixels.width.toDouble.clamped(to: resizableDimensions.widthMinMax).toIntAndClampingIfNeeded
		selectPredefinedSizeBasedOnCurrentDimensions(forceCustom: true)
	}

	private func applyPercent() {
		resizableDimensions = .percent(percent.toDouble / 100, originalSize: videoDimensions)
		print("GGG", resizableDimensions)
		width = resizableDimensions.pixels.width.toDouble.clamped(to: resizableDimensions.widthMinMax).toIntAndClampingIfNeeded
		height = resizableDimensions.pixels.height.toDouble.clamped(to: resizableDimensions.heightMinMax).toIntAndClampingIfNeeded
		print("GGG2", percent, width, height)
		selectPredefinedSizeBasedOnCurrentDimensions(forceCustom: true)
	}

	private func updateTextFieldsForCurrentDimensions() {
		width = resizableDimensions.pixels.width.toDouble.clamped(to: resizableDimensions.widthMinMax).toIntAndClampingIfNeeded
				height = resizableDimensions.pixels.height.toDouble.clamped(to: resizableDimensions.heightMinMax).toIntAndClampingIfNeeded
		percent = (resizableDimensions.percent * 100).rounded().toIntAndClampingIfNeeded
		print("FF", resizableDimensions.percent.toIntAndClampingIfNeeded)
		selectPredefinedSizeBasedOnCurrentDimensions()
	}

	private func selectPredefinedSizeBasedOnCurrentDimensions(forceCustom: Bool = false) {
		if forceCustom {
			selectedPredefinedSize = .custom
			return
		}

		guard let index = (predefinedSizes.first { size in
			guard case .dimensions(let dimensions) = size else {
				return false
			}

			return dimensions == resizableDimensions
		}) else {
			selectedPredefinedSize = .custom
			return
		}

		selectedPredefinedSize = index
	}

	private func showArrowKeyTipIfNeeded() {
		SSApp.runOnce(identifier: "DimensionsSetting_arrowKeyTip") {
			Task {
				try? await Task.sleep(for: .seconds(1))
				isArrowKeyTipPresented = true
				try? await Task.sleep(for: .seconds(10))
				isArrowKeyTipPresented = false
			}
		}
	}
}

private struct SpeedSetting: View {
	@Default(.outputSpeed) private var outputSpeed

	var body: some View {
		LabeledContent("Speed") {
			Slider(value: $outputSpeed, in: 0.5...5, step: 0.25)
			Text("\(outputSpeed.formatted(.number.precision(.fractionLength(2))))×")
				.monospacedDigit()
				.frame(width: 40, alignment: .leading)
		}
	}
}

private struct FrameRateSetting: View {
	@Default(.outputFPS) private var frameRate
	@Default(.outputSpeed) private var speed
	@State private var isHighFrameRateWarningPresented = false

	var videoFrameRate: Double

	var body: some View {
		LabeledContent("FPS") {
			Slider(
				value: $frameRate.intToDouble,
				in: range
			)
			Text("\(frameRate.formatted())")
				.monospacedDigit()
				.frame(width: 38, alignment: .leading)
		}
		.alert2(
			"Animated GIF Limitation",
			message: "Exporting GIFs with a frame rate higher than 50 is not supported as browsers will throttle and play them at 10 FPS.",
			isPresented: $isHighFrameRateWarningPresented
		)
		.onChange(of: frameRate) {
			if frameRate > 50 {
				SSApp.runOnce(identifier: "fpsWarning") {
					isHighFrameRateWarningPresented = true
				}
			}
		}
		.onAppear {
			frameRate = frameRate.clamped(to: intRange)
		}
	}

	private var maxFrameRate: Double {
		// We round it so that `29.970` becomes `30` for practical reasons.
		(videoFrameRate * speed).rounded().clamped(to: Constants.allowedFrameRate)
	}

	private var range: ClosedRange<Double> {
		.fromGraceful(
			Constants.allowedFrameRate.lowerBound,
			maxFrameRate
		)
	}

	// TODO: Make extension for this conversion.
	private var intRange: ClosedRange<Int> {
		.fromGraceful(
			Int(Constants.allowedFrameRate.lowerBound.rounded()),
			Int(maxFrameRate.rounded())
		)
	}
}

private struct QualitySetting: View {
	@Default(.outputQuality) private var quality

	var body: some View {
		LabeledContent("Quality") {
			Slider(value: $quality, in: 0.01...1)
			// We replace the non-breaking space with a word-joiner to save space.
			Text("\(quality.formatted(.percent.noFraction).replacing("\u{00A0}", with: "\u{2060}"))")
				.monospacedDigit()
				.frame(width: 38, alignment: .leading)
		}
	}
}

private struct LoopSetting: View {
	@Default(.loopGIF) private var loop
	@Default(.bounceGIF) private var bounce
	@State private var isGifLoopCountWarningPresented = false

	@Binding var loopCount: Int

	var body: some View {
		LabeledContent("Loops") {
			Stepper(
				"Loop count",
				value: $loopCount.intToDouble,
				in: 0...100,
				step: 1,
				format: .number
			)
			.labelsHidden()
			.disabled(loop)
			Toggle("Forever", isOn: $loop)
			Toggle("Bounce", isOn: $bounce)
		}
		.alert2(
			"Animated GIF Preview Limitation",
			message: "Due to a bug in the macOS GIF handling, the after-conversion preview may not loop as expected. The GIF will loop correctly in web browsers and other image viewing apps.",
			isPresented: $isGifLoopCountWarningPresented
		)
		.onChange(of: loop) {
			if loop {
				loopCount = 0
			} else {
				showConversionCompletedAnimationWarningIfNeeded()
			}
		}
	}

	private func showConversionCompletedAnimationWarningIfNeeded() {
		// NOTE: This function eventually will become an OS version check when Apple fixes their GIF animation implementation.
		// So far `NSImageView` and Quick Look are affected and may be fixed in later OS versions. Depending on how Apple fixes the issue, the message may need future modifications. Safari works as expected, so it's not all of Apple's software.
		// FB8947153: https://github.com/feedback-assistant/reports/issues/187
		SSApp.runOnce(identifier: "gifLoopCountWarning") {
			isGifLoopCountWarningPresented = true
		}
	}
}
