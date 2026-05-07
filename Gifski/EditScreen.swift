import SwiftUI
import AVFoundation

struct EditScreen: View {
	@Environment(AppState.self) private var appState
	@State private var outputCropRect = CropRect.initial
	@State private var fullPreviewStream = FullPreviewStream()

	var url: URL
	var asset: AVAsset
	var metadata: AVAsset.VideoMetadata

	init(url: URL, asset: AVAsset, metadata: AVAsset.VideoMetadata) {
		self.url = url
		self.asset = asset
		self.metadata = metadata
	}

	var body: some View {
		_EditScreen(
			url: url,
			asset: asset,
			metadata: metadata,
			outputCropRect: $outputCropRect,
			overlay: NSHostingView(rootView: CropOverlayView(
				cropRect: $outputCropRect,
				dimensions: metadata.dimensions,
				editable: appState.isCropActive
			)),
			fullPreviewStream: fullPreviewStream
		)
	}
}

private struct _EditScreen: View {
	@Environment(AppState.self) private var appState
	@Default(.outputQuality) private var outputQuality
	@Default(.bounceGIF) private var bounceGIF
	@Default(.outputFPS) private var frameRate
	@Default(.loopGIF) private var loopGIF
	@Default(.loopDelay) private var loopDelay
	@Default(.suppressKeyframeWarning) private var suppressKeyframeWarning
	@Default(.suppressLargeGIFWarning) private var suppressLargeGIFWarning
	@State private var url: URL
	@State private var asset: AVAsset
	@State private var modifiedAsset: AVAsset
	@State private var modifiedAssetTimeRange: CMTimeRange?
	@State private var metadata: AVAsset.VideoMetadata
	@State private var estimatedFileSizeModel = EstimatedFileSizeModel()
	@State private var timeRange: ClosedRange<Double>?
	@State private var loopCount = 0
	@State private var isKeyframeRateChecked = false
	@State private var isReversePlaybackWarningPresented = false
	@State private var isLargeGIFWarningPresented = false
	@State private var resizableDimensions = Dimensions.percent(1, originalSize: .init(widthHeight: 100))
	@State private var shouldShow = false
	@State private var fullPreviewState = FullPreviewGenerationEvent.initialState
	@State private var fullPreviewDebouncer = Debouncer(delay: .milliseconds(200))

	@Binding private var outputCropRect: CropRect
	@State private var savedCropRect: CropRect?
	@State private var exportModifiedVideoState = ExportModifiedVideoState.idle
	@State private var isExportModifiedVideoAudioWarningPresented = false
	private var overlay: NSView
	private let fullPreviewStream: FullPreviewStream
	@State private var lastSpeed: Double?

	init(
		url: URL,
		asset: AVAsset,
		metadata: AVAsset.VideoMetadata,
		outputCropRect: Binding<CropRect>,
		overlay: NSView,
		fullPreviewStream: FullPreviewStream
	) {
		self._url = .init(wrappedValue: url)
		self._asset = .init(wrappedValue: asset)
		self._modifiedAsset = .init(wrappedValue: asset)
		self._metadata = .init(wrappedValue: metadata)
		self._outputCropRect = outputCropRect
		self.overlay = overlay
		self.fullPreviewStream = fullPreviewStream
	}

	var body: some View {
		VStack {
			trimmingAVPlayer
			controls
			bottomBar
			ExportModifiedVideoView(
				state: $exportModifiedVideoState,
				sourceURL: url,
				isAudioWarningPresented: $isExportModifiedVideoAudioWarningPresented
			)
		}
		.background(.ultraThickMaterial)
		.navigationTitle(url.lastPathComponent)
		.navigationDocument(url)
		.toolbar {
			ToolbarSpacer(.fixed)
			if !appState.isCropActive {
				ToolbarItem {
					Toggle(
						"Preview",
						systemImage: appState.shouldShowPreview && fullPreviewState.canShowPreview ? "eye" : "eye.slash",
						isOn: appState.toggleMode(mode: .preview)
					)
					.overlay(alignment: .leading) {
						if fullPreviewState.isGenerating {
							ProgressView(value: fullPreviewState.progress)
								.progressViewStyle(.circular)
								.controlSize(.mini)
								.scaleEffect(0.8)
								.overlay {
									if let fullPreviewStateErrorMessage = fullPreviewState.errorMessage {
										Color.clear
											.popover(isPresented: .constant(true)) {
												Text(fullPreviewStateErrorMessage)
													.padding()
													.frame(maxWidth: 300)
											}
									}
								}
								.offset(x: -20)
						}
					}
				}
			}
			ToolbarSpacer(.fixed)
			ToolbarItemGroup {
				CropToolbarItems(
					isCropActive: appState.toggleMode(mode: .editCrop),
					metadata: metadata,
					outputCropRect: $outputCropRect,
					onCancel: cancelCropMode
				)
				.focusSection()
			}
		}
		.onReceive(Defaults.publisher(.outputSpeed, options: [])) { _ in
			Debouncer.debounce(delay: .seconds(0.4)) {
				Task {
					await setSpeed()
				}
			}
		}
		// We cannot use `Defaults.publisher(.outputSpeed, options: [])` without the `options` as it causes some weird glitches.
		.task {
			await setSpeed()
		}
		.onChange(of: outputQuality, initial: true) {
			estimatedFileSizeModel.duration = metadata.duration
			estimatedFileSizeModel.updateEstimate()
			updatePreviewOnSettingsChange()
		}
		// TODO: Make these a single call when tuples are equatable.
		.onChange(of: resizableDimensions) {
			estimatedFileSizeModel.updateEstimate()
			updatePreviewOnSettingsChange()
		}
		.onChange(of: timeRange) {
			estimatedFileSizeModel.updateEstimate()
			updatePreviewOnSettingsChange()
		}
		.onChange(of: bounceGIF) {
			estimatedFileSizeModel.updateEstimate()

			guard bounceGIF else {
				return
			}

			showKeyframeRateWarningIfNeeded()
		}
		.onChange(of: frameRate) {
			estimatedFileSizeModel.updateEstimate()
			updatePreviewOnSettingsChange()
		}
		.onChange(of: loopDelay) {
			updatePreviewOnSettingsChange()
		}
		.alert2(
			"Reverse Playback Preview Limitation",
			message: "Reverse playback may stutter when the video has a low keyframe rate. The GIF will not have the same stutter.",
			isPresented: $isReversePlaybackWarningPresented
		)
		.dialogSuppressionToggle(isSuppressed: $suppressKeyframeWarning)
		.alert2(
			"Large GIF",
			message: "The GIF format is very inefficient at high resolutions. The resulting file will be very large and slow to create. Consider reducing the dimensions.",
			isPresented: $isLargeGIFWarningPresented
		) {
			Button("Convert Anyway") {
				convert()
			}
			Button(role: .cancel) {}
		}
		.dialogSuppressionToggle(isSuppressed: $suppressLargeGIFWarning)
		.opacity(shouldShow ? 1 : 0)
		.onAppear {
			setUp()
			appState.onExportAsVideo = onExportAsVideo
		}
		.onDisappear {
			appState.onExportAsVideo = nil

			switch exportModifiedVideoState {
			case .idle:
				break
			case .exporting(let task, _):
				task.cancel()
			case .finished(let url):
				try? FileManager.default.removeItem(at: url)
			}
		}
		.task {
			try? await Task.sleep(for: .seconds(0.3))

			withAnimation {
				shouldShow = true
			}
		}
		.task {
			for await event in fullPreviewStream.eventStream {
				fullPreviewState = event
			}
		}
		.onKeyboardShortcut(.escape, modifiers: []) {
			if appState.isCropActive {
				cancelCropMode()
			}
		}
	}

	private func cancelCropMode() {
		if let savedCropRect {
			outputCropRect = savedCropRect
		}
		appState.mode = .normal
	}

	private func onExportAsVideo() {
		switch exportModifiedVideoState {
		case .idle:
			break
		case .exporting, .finished:
			// If another alert (like bounce warning) occurs when you activate this callback, the `fileExporter` modifier won't show and the state will be stuck on `.finished`. By reassigning the state this will force a swiftUI draw and bring up the file exporter.
			exportModifiedVideoState = exportModifiedVideoState
			return
		}

		if metadata.hasAudio {
			SSApp.runOnce(identifier: "audioTrackExportWarning") {
				isExportModifiedVideoAudioWarningPresented = true
			}
		}

		exportModifiedVideoState = .exporting(
			Task {
				do {
					let outputURL = try await exportModifiedVideo(conversion: conversionSettings)
					try await MainActor.run {
						try Task.checkCancellation()
						exportModifiedVideoState = .finished(outputURL)
					}
				} catch {
					if Task.isCancelled || error.isCancelled {
						return
					}
					await MainActor.run {
						exportModifiedVideoState = .idle
						appState.error = error
					}
				}
			},
			videoIsOverTwentySeconds: conversionSettings.gifDuration(assetTimeRange: modifiedAssetTimeRange, withBounce: false) > .seconds(20)
		)
	}

	private func updatePreviewOnSettingsChange() {
		guard appState.mode != .editCrop else {
			return
		}

		fullPreviewDebouncer {
			Task {
				let conversion = conversionSettings

				await fullPreviewStream.requestNewFullPreview(
					asset: conversion.asset,
					settingsEvent: .init(
						conversion: conversion,
						speed: Defaults[.outputSpeed],
						framesPerSecondsWithoutSpeedAdjustment: Defaults[.outputFPS],
						duration: metadata.duration.toTimeInterval
					)
				)
			}
		}
	}

	private func setSpeed() async {
		do {
			if Defaults[.outputSpeed] == lastSpeed {
				return
			}
			lastSpeed = Defaults[.outputSpeed]
			// We could have set the `rate` of the player instead of modifying the asset, but it's just easier to modify the asset as then it matches what we want to generate. Otherwise, we would have to translate trimming ranges to the correct speed, etc.

			let changedSpeedAsset = try await asset.firstVideoTrack?.extractToNewAssetAndChangeSpeed(to: Defaults[.outputSpeed]) ?? modifiedAsset
			modifiedAsset = try await PreviewableComposition(extractPreviewableCompositionFrom: changedSpeedAsset)
			modifiedAssetTimeRange = try await changedSpeedAsset.firstVideoTrack?.load(.timeRange)

			estimatedFileSizeModel.updateEstimate()
			updatePreviewOnSettingsChange()
		} catch {
			appState.error = error
		}
	}

	private func setUp() {
		estimatedFileSizeModel.getConversionSettings = { conversionSettings }
		updatePreviewOnSettingsChange()
	}

	/**
	Paused because the preview is generating the new preview.
	*/
	var previewPaused: Bool {
		appState.shouldShowPreview && fullPreviewState.isGenerating
	}

	private var trimmingAVPlayer: some View {
		// TODO: Move the trimmer outside the video view.
		TrimmingAVPlayer(
			asset: modifiedAsset,
			shouldShowPreview: appState.shouldShowPreview,
			fullPreviewState: fullPreviewState,
			loopPlayback: loopGIF,
			bouncePlayback: bounceGIF,
			speed: previewPaused ? 0.0 : 1.0,
			overlay: appState.shouldShowPreview ? nil : overlay,
			isPlayPauseButtonEnabled: !previewPaused,
			isTrimmerCollapsible: appState.isCropActive
		) { timeRange in
			DispatchQueue.main.async {
				guard self.timeRange != timeRange else {
					return
				}

				self.timeRange = timeRange
				estimatedFileSizeModel.updateEstimate()
				updatePreviewOnSettingsChange()
			}
		}
		.onChange(of: appState.mode) {
			if appState.mode == .editCrop {
				savedCropRect = outputCropRect
				Task {
					await fullPreviewStream.cancelFullPreviewGeneration()
				}
			} else {
				savedCropRect = nil
			}

			// Because we don't update the preview during editCrop, the preview may be stale.
			updatePreviewOnSettingsChange()
		}
	}

	private var controls: some View {
		HStack(spacing: 0) {
			Form {
				DimensionsSetting(
					maximumDimensions: outputDimensionsMaximumSize,
					resizableDimensions: $resizableDimensions
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
				if
					!suppressLargeGIFWarning,
					resizableDimensions.pixels.longestSide >= 1200,
					conversionSettings.gifDuration(assetTimeRange: modifiedAssetTimeRange) > .seconds(5)
				{
					isLargeGIFWarningPresented = true
				} else {
					convert()
				}
			}
			.keyboardShortcut(.defaultAction)
			.disabled(!hasEnoughFrames)
			.padding(.top, -1) // Makes the bar have equal spacing on top and bottom.
		}
		.overlay {
			if hasEnoughFrames {
				EstimatedFileSizeView(model: estimatedFileSizeModel)
			} else {
				Label("Not enough frames. Increase the duration or frame rate.", systemImage: "exclamationmark.triangle.fill")
					.foregroundStyle(.yellow)
					.font(.caption)
			}
		}
		.padding()
		.padding(.top, -16)
	}

	private var hasEnoughFrames: Bool {
		let duration = conversionSettings.gifDuration(assetTimeRange: modifiedAssetTimeRange, withBounce: false)
		return Int(duration.toTimeInterval * Double(frameRate)) >= 2
	}

	private var outputDimensionsMaximumSize: CGSize {
		outputCropRect
			.unnormalize(forDimensions: metadata.dimensions)
			.size
			.rounded()
	}

	private var outputRenderSize: CGSize {
		outputCropRect.renderSize(forCroppedOutputSize: resizableDimensions.pixels)
	}

	private func convert() {
		appState.navigationPath.append(.conversion(conversionSettings))
	}

	private var conversionSettings: GIFGenerator.Conversion {
		.init(
			asset: modifiedAsset,
			sourceURL: url,
			timeRange: timeRange,
			quality: outputQuality,
			dimensions: outputRenderSize.toInt,
			outputDimensions: resizableDimensions.pixels.toInt,
			frameRate: frameRate,
			loop: {
				guard loopGIF else {
					return loopCount == 0 ? .never : .count(loopCount)
				}

				return .forever
			}(),
			bounce: bounceGIF,
			loopDelay: Defaults[.loopDelay],
			crop: outputCropRect,
			trackPreferredTransform: metadata.trackPreferredTransform
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
					let keyframeInfo = try await modifiedAsset.firstVideoTrack?.keyframeInfo(),
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
	case dimensions(Dimensions)

	static func selectedPredefinedSize(
		resizableDimensions: Dimensions,
		predefinedPixelDimensions: [Dimensions],
		predefinedPercentDimensions: [Dimensions],
		activeDimensionType: DimensionType,
		forceCustom: Bool = false
	) -> Self {
		if forceCustom {
			return .custom
		}

		switch activeDimensionType {
		case .pixels:
			guard
				let selectedDimensions = predefinedPixelDimensions.first(where: { $0 == resizableDimensions })
			else {
				/*
				Do not auto-select a percent preset while editing pixels.
				Changing `selectedPredefinedSize` triggers `updateDimensionsBasedOnSelection`, which would switch `dimensionsType` to percent and unexpectedly flip the input mode.
				*/
				return .custom
			}

			return .dimensions(selectedDimensions)
		case .percent:
			guard
				let selectedDimensions = predefinedPercentDimensions.first(where: { $0 == resizableDimensions })
			else {
				/*
				Do not auto-select a pixel preset while editing percent.
				This keeps the current input mode stable and avoids a surprising type switch.
				*/
				return .custom
			}

			return .dimensions(selectedDimensions)
		}
	}
}

private struct DimensionsSetting: View {
	@State private var predefinedPixelDimensions = [Dimensions]()
	@State private var predefinedPercentDimensions = [Dimensions]()
	@State private var selectedPredefinedSize = PredefinedSizeItem.custom
	@State private var dimensionsType = DimensionType.pixels
	@State private var width = 0
	@State private var height = 0
	@State private var percent = 0
	@State private var isSynchronizingTextFields = false
	@State private var isArrowKeyTipPresented = false

	let maximumDimensions: CGSize
	@Binding var resizableDimensions: Dimensions // TODO: Rename.

	var body: some View {
		VStack(spacing: 16) {
			Picker("Dimensions", selection: $selectedPredefinedSize) {
				if selectedPredefinedSize == .custom {
					let string = switch dimensionsType {
					case .pixels:
						resizableDimensions.percentFormatted
					case .percent:
						resizableDimensions.pixels.formatted
					}

					Text("Custom — \(string)")
						.tag(PredefinedSizeItem.custom)
				}
				Section("Pixel sizes") {
					ForEach(predefinedPixelDimensions, id: \.self) { dimensions in
						let predefinedSize = PredefinedSizeItem.dimensions(dimensions)
						Text("\(dimensions.description)")
							.tag(predefinedSize)
					}
				}
				Section("Exact percent") {
					ForEach(predefinedPercentDimensions, id: \.self) { dimensions in
						let predefinedSize = PredefinedSizeItem.dimensions(dimensions)
						Text("\(dimensions.description)")
							.tag(predefinedSize)
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
						let textFieldWidth = 44.0
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
									guard !isSynchronizingTextFields else {
										return
									}

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
									guard !isSynchronizingTextFields else {
										return
									}

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
							.frame(width: 36)
							.onChange(of: percent) {
								guard !isSynchronizingTextFields else {
									return
								}

								applyPercent()
							}
						}
					}
				}
				.padding(.trailing, -8)
				Picker("Dimension type", selection: $dimensionsType) {
					ForEach(DimensionType.allCases, id: \.self) {
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
		}
		.onAppear {
			setUpDimensions()
			updateTextFieldsForCurrentDimensions()
			showArrowKeyTipIfNeeded()
		}
		.onChange(of: maximumDimensions) {
			updateMaximumDimensions()
		}
	}

	private func setUpDimensions() {
		let dimensions = Dimensions.pixels(maximumDimensions, originalSize: maximumDimensions)

		resizableDimensions = dimensions
		updatePredefinedDimensions()
	}

	private func updatePredefinedDimensions() {
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

		if !pixelCommonSizes.contains(maximumDimensions.width) {
			pixelCommonSizes.append(maximumDimensions.width)
			pixelCommonSizes.sort(by: >)
		}

		let pixelDimensions = pixelCommonSizes.map { width in
			let ratio = width / maximumDimensions.width
			let height = maximumDimensions.height * ratio
			return CGSize(width: width, height: height).rounded()
		}
		.filter { $0.width <= maximumDimensions.width && $0.height <= maximumDimensions.height }

		let predefinedPixelDimensions = pixelDimensions
			// TODO
//			.filter { resizableDimensions.validate(newSize: $0) }
			.map { Dimensions.pixels($0, originalSize: maximumDimensions) }

		let percentCommonSizes: [Double] = [
			100,
			50,
			33,
			25,
			20
		]

		let predefinedPercentDimensions = percentCommonSizes.map {
			Dimensions.percent($0 / 100, originalSize: maximumDimensions)
		}

		self.predefinedPixelDimensions = predefinedPixelDimensions
		self.predefinedPercentDimensions = predefinedPercentDimensions
		selectPredefinedSizeBasedOnCurrentDimensions()
	}

	private func updateDimensionsBasedOnSelection(_ selectedSize: PredefinedSizeItem) {
		guard case .dimensions(let dimensions) = selectedSize else {
			synchronizeTextFieldsWithCurrentDimensions()
			return
		}

		dimensionsType = dimensions.isPercent ? .percent : .pixels
		resizableDimensions = dimensions

		synchronizeTextFieldsWithCurrentDimensions()
	}

	private func applyWidth() {
		guard dimensionsType == .pixels else {
			selectPredefinedSizeBasedOnCurrentDimensions()
			return
		}

		let currentWidth = resizableDimensions.pixels.width.toDouble.clamped(to: resizableDimensions.widthMinMax).toIntAndClampingIfNeeded
		guard width != currentWidth else {
			selectPredefinedSizeBasedOnCurrentDimensions()
			return
		}

		let previousDimensions = resizableDimensions
		resizableDimensions = resizableDimensions.aspectResized(usingWidth: width.toDouble)
		synchronizeTextFieldsWithCurrentDimensions()
		selectPredefinedSizeBasedOnCurrentDimensions(forceCustom: previousDimensions != resizableDimensions)
	}

	private func applyHeight() {
		guard dimensionsType == .pixels else {
			selectPredefinedSizeBasedOnCurrentDimensions()
			return
		}

		let currentHeight = resizableDimensions.pixels.height.toDouble.clamped(to: resizableDimensions.heightMinMax).toIntAndClampingIfNeeded
		guard height != currentHeight else {
			selectPredefinedSizeBasedOnCurrentDimensions()
			return
		}

		let previousDimensions = resizableDimensions
		resizableDimensions = resizableDimensions.aspectResized(usingHeight: height.toDouble)
		synchronizeTextFieldsWithCurrentDimensions()
		selectPredefinedSizeBasedOnCurrentDimensions(forceCustom: previousDimensions != resizableDimensions)
	}

	private func applyPercent() {
		guard dimensionsType == .percent else {
			selectPredefinedSizeBasedOnCurrentDimensions()
			return
		}

		let currentPercent = (resizableDimensions.percent * 100).rounded().toIntAndClampingIfNeeded
		guard percent != currentPercent else {
			selectPredefinedSizeBasedOnCurrentDimensions()
			return
		}

		let previousDimensions = resizableDimensions
		resizableDimensions = .percent(percent.toDouble / 100, originalSize: maximumDimensions)
		synchronizeTextFieldsWithCurrentDimensions()
		selectPredefinedSizeBasedOnCurrentDimensions(forceCustom: previousDimensions != resizableDimensions)
	}

	private func updateMaximumDimensions() {
		resizableDimensions = resizableDimensions.withOriginalSizePreservingPercent(maximumDimensions)
		updatePredefinedDimensions()
		updateTextFieldsForCurrentDimensions()
	}

	private func updateTextFieldsForCurrentDimensions() {
		synchronizeTextFieldsWithCurrentDimensions()
		selectPredefinedSizeBasedOnCurrentDimensions()
	}

	private func synchronizeTextFieldsWithCurrentDimensions() {
		isSynchronizingTextFields = true
		defer {
			isSynchronizingTextFields = false
		}

		width = resizableDimensions.pixels.width.toDouble.clamped(to: resizableDimensions.widthMinMax).toIntAndClampingIfNeeded
		height = resizableDimensions.pixels.height.toDouble.clamped(to: resizableDimensions.heightMinMax).toIntAndClampingIfNeeded
		percent = (resizableDimensions.percent * 100).rounded().toIntAndClampingIfNeeded
	}

	private func selectPredefinedSizeBasedOnCurrentDimensions(forceCustom: Bool = false) {
		selectedPredefinedSize = PredefinedSizeItem.selectedPredefinedSize(
			resizableDimensions: resizableDimensions,
			predefinedPixelDimensions: predefinedPixelDimensions,
			predefinedPercentDimensions: predefinedPercentDimensions,
			activeDimensionType: dimensionsType,
			forceCustom: forceCustom
		)
	}

	private func showArrowKeyTipIfNeeded() {
		SSApp.runOnce(identifier: "DimensionsSetting_arrowKeyTip") {
			Task {
				try await Task.sleep(for: .seconds(1))
				isArrowKeyTipPresented = true
				try await Task.sleep(for: .seconds(10))
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
	@Default(.loopDelay) private var loopDelay
	@State private var isGifLoopCountWarningPresented = false
	@State private var isMoreOptionsPopoverPresented = false

	@Binding var loopCount: Int

	var body: some View {
		LabeledContent("Loops") {
			HStack {
				Stepper(
					"Loop count",
					value: $loopCount.intToDouble,
					in: 0...100,
					step: 1,
					format: .number
				)
				.labelsHidden()
				.disabled(loop)
				Button("More Options", systemImage: "ellipsis") {
					isMoreOptionsPopoverPresented.toggle()
				}
				.labelFillVertical()
				.labelStyle(.iconOnly)
				.buttonStyle(.accessoryBar)
				.controlSize(.small)
				.popover(isPresented: $isMoreOptionsPopoverPresented) {
					LabeledContent("Loop delay") {
						Stepper(
							"Loop delay",
							value: $loopDelay,
							in: 0...10,
							step: 0.5,
							format: .number.precision(.fractionLength(1))
						)
						.labelsHidden()
						Text("s")
							.foregroundStyle(.secondary)
					}
					.padding()
				}
				Toggle("Forever", isOn: $loop)
				Toggle("Bounce", isOn: $bounce)
			}
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
