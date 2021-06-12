import SwiftUI
import Combine
import AVKit
import Defaults

final class EditVideoViewController: NSViewController {
	enum PredefinedSizeItem {
		case custom
		case spacer
		case dimensions(ResizableDimensions)

		var resizableDimensions: ResizableDimensions? {
			switch self {
			case .dimensions(let resizableDimensions):
				return resizableDimensions
			default:
				return nil
			}
		}
	}

	@IBOutlet private var estimatedSizeView: NSView!
	@IBOutlet private var frameRateSlider: NSSlider!
	@IBOutlet private var frameRateLabel: NSTextField!
	@IBOutlet private var qualitySlider: NSSlider!
	@IBOutlet private var loopCheckbox: NSButton!

	@IBOutlet private var widthTextField: IntTextField!
	@IBOutlet private var heightTextField: IntTextField!
	@IBOutlet private var predefinedSizesDropdown: MenuPopUpButton!
	@IBOutlet private var dimensionsTypeDropdown: MenuPopUpButton!
	@IBOutlet private var cancelButton: NSButton!
	@IBOutlet private var playerViewWrapper: NSView!
	@IBOutlet private var loopCountTextField: IntTextField!
	@IBOutlet private var loopCountStepper: NSStepper!

	private var cancellables = Set<AnyCancellable>()

	var inputUrl: URL!
	var asset: AVAsset!
	var videoMetadata: AVAsset.VideoMetadata!

	private var resizableDimensions: ResizableDimensions!
	private var predefinedSizes: [PredefinedSizeItem]!
	private var playerViewController: TrimmingAVPlayerViewController!
	private var isKeyframeRateChecked = false

	private var timeRange: ClosedRange<Double>? { playerViewController?.timeRange }

	private lazy var estimatedFileSizeModel = EstimatedFileSizeModel(
		getConversionSettings: { self.conversionSettings },
		getNaiveEstimate: getNaiveEstimate,
		getIsConverting: { self.isConverting }
	)

	private let tooltip = Tooltip(
		identifier: "savePanelArrowKeys",
		text: "Press the arrow up/down keys to change the value by 1. Hold the Option key meanwhile to change it by 10.",
		showOnlyOnce: true,
		maxWidth: 300
	)

	private var loopCount: Int {
		/*
		Looping values are:
		 -1 | No loops
		  0 | Loop forever
		>=1 | Loop n times
		*/
		guard Defaults[.loopGif] else {
			return Int(loopCountTextField.intValue) == 0 ? -1 : Int(loopCountTextField.intValue)
		}

		return 0
	}

	private var conversionSettings: Gifski.Conversion {
		.init(
			video: inputUrl,
			timeRange: timeRange,
			quality: Defaults[.outputQuality],
			dimensions: resizableDimensions.changed(dimensionsType: .pixels).currentDimensions.value,
			frameRate: frameRateSlider.integerValue,
			loopCount: loopCount,
			bounce: Defaults[.bounceGif]
		)
	}

	convenience init(
		inputUrl: URL,
		asset: AVAsset,
		videoMetadata: AVAsset.VideoMetadata
	) {
		self.init()

		self.inputUrl = inputUrl
		self.asset = asset
		self.videoMetadata = videoMetadata

		AppDelegate.shared.previousEditViewController = self
	}

	var isConverting = false

	@IBAction
	private func convert(_ sender: Any) {
		isConverting = true

		estimatedFileSizeModel.cancel()

		let convert = ConversionViewController(conversion: conversionSettings)
		push(viewController: convert)
	}

	@IBAction
	private func cancel(_ sender: Any) {
		let videoDropController = VideoDropViewController()
		push(viewController: videoDropController)
		AppDelegate.shared.previousEditViewController = nil
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		setUpDimensions()
		setUpDropdowns()
		setUpSliders()
		setUpWidthAndHeightTextFields()
		setUpLoopCountControls()
		setUpDropView()
		setUpTrimmingView()
		setUpEstimatedFileSizeView()
	}

	override func viewDidAppear() {
		super.viewDidAppear()

		view.window?.makeFirstResponder(playerViewController.playerView)
		setUpTabOrder()

		tooltip.show(from: widthTextField, preferredEdge: .maxX)
	}

	private func setUpEstimatedFileSizeView() {
		let view = EstimatedFileSizeView(model: estimatedFileSizeModel)
		let hostingView = NSHostingView(rootView: view)
		estimatedSizeView.addSubview(hostingView)
		hostingView.constrainEdgesToSuperview()
	}

	private func setUpDimensions() {
		let minimumScale: CGFloat = 0.01
		let maximumScale: CGFloat = 1
		let dimensions = Dimensions(type: .pixels, value: videoMetadata.dimensions)

		resizableDimensions = ResizableDimensions(
			dimensions: dimensions,
			minimumScale: minimumScale,
			maximumScale: maximumScale
		)

		var pixelCommonSizes: [CGFloat] = [
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

		if !pixelCommonSizes.contains(dimensions.value.width) {
			pixelCommonSizes.append(dimensions.value.width)
			pixelCommonSizes.sort(by: >)
		}

		let pixelDimensions = pixelCommonSizes.map { width -> CGSize in
			let ratio = width / dimensions.value.width
			let height = dimensions.value.height * ratio
			return CGSize(width: width, height: height)
		}

		let predefinedPixelDimensions = pixelDimensions
			.filter { resizableDimensions.validate(newSize: $0) }
			.map { resizableDimensions.resized(to: $0) }

		let percentCommonSizes: [CGFloat] = [
			50,
			33,
			25,
			20
		]

		let predefinedPercentDimensions = percentCommonSizes
			.map {
				resizableDimensions.changed(dimensionsType: .percent)
					.resized(to: CGSize(width: $0, height: $0))
			}

		predefinedSizes = [.custom]
		predefinedSizes.append(.spacer)
		predefinedSizes.append(contentsOf: predefinedPixelDimensions.map { .dimensions($0) })
		predefinedSizes.append(.spacer)
		predefinedSizes.append(contentsOf: predefinedPercentDimensions.map { .dimensions($0) })
	}

	private func setUpDropdowns() {
		predefinedSizesDropdown.removeAllItems()

		for size in predefinedSizes {
			switch size {
			case .custom:
				predefinedSizesDropdown.addItem(withTitle: "Custom")
			case .spacer:
				predefinedSizesDropdown.menu?.addItem(.separator())
			case .dimensions(let dimensions):
				predefinedSizesDropdown.addItem(withTitle: "\(dimensions)")
			}
		}

		predefinedSizesDropdown.onMenuWillOpen = { [weak self] in
			self?.predefinedSizesDropdown.item(at: 0)?.title = "Custom"
		}

		predefinedSizesDropdown.onMenuDidClose = { [weak self] selectedIndex in
			guard let self = self else {
				return
			}

			let oldOrNewSelectedIndex = selectedIndex ?? self.predefinedSizesDropdown.indexOfSelectedItem

			if
				let size = self.predefinedSizes?[safe: oldOrNewSelectedIndex],
				case .custom = size
			{
				// We don't care if it's newly selected index or not, if it's custom, set its size
				self.updateSelectedItemAsCustomWithSize()
			} else if
				let index = selectedIndex, let size = self.predefinedSizes?[safe: index],
				case .dimensions(let dimensions) = size
			{
				// But we care if it's newly selected index for dimensions, we don't want to recalculate
				// if we don't have to
				self.resizableDimensions.change(dimensionsType: dimensions.currentDimensions.type)
				self.resizableDimensions.resize(to: dimensions.currentDimensions.value)
				self.dimensionsUpdated()
			}
		}

		dimensionsTypeDropdown.removeAllItems()
		dimensionsTypeDropdown.addItems(withTitles: DimensionsType.allCases.map(\.rawValue))

		dimensionsTypeDropdown.onMenuDidClose = { [weak self] selectedIndex in
			guard
				let self = self,
				let index = selectedIndex,
				let item = self.dimensionsTypeDropdown.item(at: index),
				let dimensionsType = DimensionsType(rawValue: item.title)
			else {
				return
			}

			self.resizableDimensions.change(dimensionsType: dimensionsType)
			self.dimensionsUpdated()
			self.updateTextFieldsMinMax()
		}

		if resizableDimensions.currentDimensions.value.width > 640 {
			predefinedSizesDropdown.selectItem(at: 3)
		} else {
			predefinedSizesDropdown.selectItem(at: 2)
		}

		dimensionsUpdated()
	}

	private func setUpSliders() {
		frameRateSlider.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			let frameRate = self.frameRateSlider.integerValue
			self.frameRateLabel.stringValue = "\(frameRate)"
			self.estimatedFileSizeModel.updateEstimate()
		}

		qualitySlider.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			Defaults[.outputQuality] = self.qualitySlider.doubleValue
			self.estimatedFileSizeModel.updateEstimate()
		}

		// We round it so that `29.970` becomes `30` for practical reasons.
		let frameRate = videoMetadata.frameRate.rounded()

		if frameRate > 50 {
			showFpsWarningIfNeeded()
		}

		frameRateSlider.maxValue = frameRate.clamped(to: Constants.allowedFrameRate)
		frameRateSlider.doubleValue = defaultFrameRate(inputFrameRate: frameRate)
		frameRateSlider.triggerAction()

		qualitySlider.doubleValue = Defaults[.outputQuality]
		qualitySlider.triggerAction()
	}

	private func showFpsWarningIfNeeded() {
		SSApp.runOnce(identifier: "fpsWarning") {
			DispatchQueue.main.async { [self] in
				NSAlert.showModal(
					for: view.window,
					title: "Animated GIF Limitation",
					message: "Exporting GIFs with a frame rate higher than 50 is not supported as browsers will throttle and play them at 10 FPS.",
					defaultButtonIndex: -1
				)
			}
		}
	}

	private func showConversionCompletedAnimationWarningIfNeeded() {
		// TODO: This function eventually will become an OS version check when Apple fixes their GIF animation implementation.
		// So far `NSImageView` and Quick Look are affected and may be fixed in later OS versions. Depending on how Apple fixes the issue,
		// the message may need future modifications. Safari works as expected, so it's not all of Apple's software.
		// https://github.com/feedback-assistant/reports/issues/187
		SSApp.runOnce(identifier: "gifLoopCountWarning") {
			DispatchQueue.main.async { [self] in
				NSAlert.showModal(
					for: view.window,
					title: "Animated GIF Preview Limitation",
					message: "Due to a bug in the macOS GIF handling, the after-conversion preview and Quick Look may not loop as expected. The GIF will loop correctly in web browsers and other image viewing apps.",
					defaultButtonIndex: -1
				)
			}
		}
	}

	private func showKeyframeRateWarningIfNeeded(maximumKeyframeInterval: Double = 30) {
		guard !isKeyframeRateChecked, !Defaults[.suppressKeyframeWarning] else {
			return
		}

		isKeyframeRateChecked = true

		DispatchQueue.global(qos: .utility).async { [weak self] in
			guard
				let keyframeInfo = self?.asset.firstVideoTrack?.getKeyframeInfo(),
				keyframeInfo.keyframeInterval > maximumKeyframeInterval
			else {
				return
			}

			print("Low keyframe interval \(keyframeInfo.keyframeInterval)")

			DispatchQueue.main.async { [weak self] in
				guard let self = self else {
					return
				}

				let alert = NSAlert(
					title: "Reverse Playback Preview Limitation",
					message: "Reverse playback may stutter when the video has a low keyframe rate. The GIF will not have the same stutter.",
					defaultButtonIndex: -1
				)

				alert.showsSuppressionButton = true
				alert.runModal(for: self.view.window)

				if alert.suppressionButton?.state == .on {
					Defaults[.suppressKeyframeWarning] = true
				}
			}
		}
	}

	private func setUpWidthAndHeightTextFields() {
		widthTextField.onBlur = { [weak self] width in
			self?.resizableDimensions.resize(usingWidth: CGFloat(width))
			self?.dimensionsUpdated()
		}

		widthTextField.onValueChange = { [weak self] width in
			guard let self = self else {
				return
			}

			self.resizableDimensions.resize(usingWidth: CGFloat(width))
			self.dimensionsUpdated()
		}

		heightTextField.onBlur = { [weak self] height in
			self?.resizableDimensions.resize(usingHeight: CGFloat(height))
			self?.dimensionsUpdated()
		}

		heightTextField.onValueChange = { [weak self] height in
			guard let self = self else {
				return
			}

			self.resizableDimensions.resize(usingHeight: CGFloat(height))
			self.dimensionsUpdated()
		}

		updateTextFieldsMinMax()
	}

	private func setUpLoopCountControls() {
		loopCountTextField.onBlur = { [weak self] loopCount in
			guard let self = self else {
				return
			}

			self.loopCountTextField.stringValue = "\(loopCount)"
			self.loopCountStepper.intValue = Int32(loopCount)

			if loopCount > 0 {
				self.loopCheckbox.state = .off
			}
		}

		loopCountTextField.onValueChange = { [weak self] loopCount in
			guard let self = self else {
				return
			}

			let validLoopCount = loopCount.clamped(to: Constants.loopCountRange)
			self.loopCountTextField.stringValue = "\(validLoopCount)"
			self.loopCountStepper.intValue = Int32(validLoopCount)

			if validLoopCount > 0 {
				self.loopCheckbox.state = .off
			}
		}

		loopCheckbox.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			if self.loopCheckbox.state == .on {
				self.loopCountTextField.stringValue = "0"
				self.loopCountStepper.intValue = 0
			} else {
				self.showConversionCompletedAnimationWarningIfNeeded()
			}
		}

		Defaults.publisher(.loopGif)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] in
				self?.loopCountTextField.isEnabled = !$0.newValue
				self?.loopCountStepper.isEnabled = !$0.newValue
			}
			.store(in: &cancellables)


		loopCountStepper.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			self.loopCountTextField.stringValue = "\(self.loopCountStepper.intValue)"
		}
	}

	private func setUpDropView() {
		let videoDropController = VideoDropViewController(dropLabelIsHidden: true)
		add(childController: videoDropController)
	}

	private func setUpTrimmingView() {
		playerViewController = TrimmingAVPlayerViewController(playerItem: AVPlayerItem(asset: asset)) { [weak self] _ in
			self?.estimatedFileSizeModel.updateEstimate()
		}

		Defaults.publisher(.loopGif)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] in
				self?.playerViewController.loopPlayback = $0.newValue
			}
			.store(in: &cancellables)

		Defaults.publisher(.bounceGif)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] in
				self?.playerViewController.bouncePlayback = $0.newValue
				self?.estimatedFileSizeModel.updateEstimate()
			}
			.store(in: &cancellables)

		playerViewController.playerView.player?.publisher(for: \.rate, options: [.new])
			.sink { [weak self] rate in
				guard rate == -1 else {
					return
				}

				self?.showKeyframeRateWarningIfNeeded()
			}
			.store(in: &cancellables)

		add(childController: playerViewController, to: playerViewWrapper)
	}

	private func setUpTabOrder() {
		if let button = view.window?.firstResponder as? NSButton {
			button.nextKeyView = predefinedSizesDropdown
		}

		predefinedSizesDropdown.nextKeyView = widthTextField
		widthTextField.nextKeyView = heightTextField
		heightTextField.nextKeyView = dimensionsTypeDropdown
		dimensionsTypeDropdown.nextKeyView = frameRateSlider
		frameRateSlider.nextKeyView = qualitySlider
		qualitySlider.nextKeyView = loopCountTextField
		loopCountTextField.nextKeyView = loopCheckbox
		loopCheckbox.nextKeyView = cancelButton
	}

	private func updateTextFieldsMinMax() {
		let widthMinMax = resizableDimensions.widthMinMax
		let heightMinMax = resizableDimensions.heightMinMax
		widthTextField.minMax = Int(widthMinMax.lowerBound)...Int(widthMinMax.upperBound)
		heightTextField.minMax = Int(heightMinMax.lowerBound)...Int(heightMinMax.upperBound)
		loopCountTextField.minMax = Constants.loopCountRange
	}

	private func dimensionsUpdated() {
		updateDimensionsDisplay()
		estimatedFileSizeModel.updateEstimate()
		selectPredefinedSizeBasedOnCurrentDimensions()
	}

	private func updateDimensionsDisplay() {
		widthTextField.stringValue = String(format: "%.0f", resizableDimensions.currentDimensions.value.width)
		heightTextField.stringValue = String(format: "%.0f", resizableDimensions.currentDimensions.value.height)
		dimensionsTypeDropdown.selectItem(withTitle: resizableDimensions.currentDimensions.type.rawValue)
	}

	private func selectPredefinedSizeBasedOnCurrentDimensions() {
		// First reset the state.
		predefinedSizesDropdown.selectItem(at: NSNotFound)

		// Check if we can select predefined option that has the same dimensions settings.
		if let index = predefinedSizes.firstIndex(where: { $0.resizableDimensions?.currentDimensions == resizableDimensions.currentDimensions }) {
			predefinedSizesDropdown.selectItem(at: index)
		} else {
			updateSelectedItemAsCustomWithSize()
		}
	}

	private func updateSelectedItemAsCustomWithSize() {
		let newType: DimensionsType = resizableDimensions.currentDimensions.type == .percent ? .pixels : .percent
		let newResizableDimensions = resizableDimensions.changed(dimensionsType: newType)
		let selectedCustomTitle = "Custom - \(newResizableDimensions.currentDimensions)"
		predefinedSizesDropdown.item(at: 0)?.title = selectedCustomTitle
		predefinedSizesDropdown.selectItem(at: 0)
	}

	private func defaultFrameRate(inputFrameRate frameRate: Double) -> Double {
		frameRate.clamped(to: Constants.allowedFrameRate.lowerBound...20)
	}

	private func getNaiveEstimate() -> Double {
		let duration: Double = {
			guard let timeRange = timeRange else {
				return videoMetadata.duration
			}

			return timeRange.upperBound - timeRange.lowerBound
		}()

		let frameCount = duration * frameRateSlider.doubleValue
		let dimensions = resizableDimensions.changed(dimensionsType: .pixels).currentDimensions.value
		var fileSize = (Double(dimensions.width) * Double(dimensions.height) * frameCount) / 3
		fileSize = fileSize * (qualitySlider.doubleValue + 1.5) / 2.5

		return fileSize
	}
}
