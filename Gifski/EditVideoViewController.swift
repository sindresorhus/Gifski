import Cocoa
import AVKit

import AVFoundation

final class TrimmingAVPlayerView: AVPlayerView {
	private var timeRangeObserver: NSKeyValueObservation?

	func observeTrimmedTimeRange(_ updateClosure: @escaping (ClosedRange<Double>) -> Void) {
		timeRangeObserver = player?.currentItem?.observe(\.duration, options: [.new]) { item, _ in
			let startTime = item.reversePlaybackEndTime.seconds
			let endTime = item.forwardPlaybackEndTime.seconds
			if !startTime.isNaN && !endTime.isNaN {
				updateClosure(startTime...endTime)
			}
		}
	}

	func hideTrimButtons() {
		let avTrimView = firstSubview(where: { $0.description.contains("AVTrimView") }, deep: true)

		if let avTrimView = avTrimView {
			let superview = avTrimView.superview
			if let leftConstraint = superview?.constraints.first(where: { constraint -> Bool in
				let firstCheck = (constraint.firstItem as? NSView) == avTrimView && constraint.firstAttribute == .right
				let secondCheck = (constraint.secondItem as? NSView) == avTrimView && constraint.secondAttribute == .right
				return firstCheck || secondCheck
			}) {
				superview?.removeConstraint(leftConstraint)
				NSLayoutConstraint(item: leftConstraint.firstItem, attribute: .right, relatedBy: leftConstraint.relation, toItem: leftConstraint.secondItem, attribute: leftConstraint.secondAttribute, multiplier: leftConstraint.multiplier, constant: leftConstraint.constant).isActive = true
			}
			let subviewsToHide = superview?.subviews
				.filter { $0 != avTrimView }
				.first?
				.subviews
				.filter { ($0 as? NSButton)?.image == nil }
			subviewsToHide?.forEach { subview in
				let button = subview as? NSButton
				button?.isHidden = true
			}
		}
	}
}

final class EditVideoViewController: NSViewController {
	enum PredefinedSizeItem {
		case custom
		case spacer
		case dimensions(ResizableDimensions)

		var resizableDimensions: ResizableDimensions? {
			switch self {
			case let .dimensions(resizableDimensions):
				return resizableDimensions
			default:
				return nil
			}
		}
	}

	@IBOutlet private var estimatedSizeLabel: NSTextField!
	@IBOutlet private var frameRateSlider: NSSlider!
	@IBOutlet private var frameRateLabel: NSTextField!
	@IBOutlet private var qualitySlider: NSSlider!

	@IBOutlet private var widthTextField: IntTextField!
	@IBOutlet private var heightTextField: IntTextField!
	@IBOutlet private var predefinedSizesDropdown: MenuPopUpButton!
	@IBOutlet private var dimensionsTypeDropdown: MenuPopUpButton!

	@IBOutlet private var playerView: TrimmingAVPlayerView!

	var inputUrl: URL!
	var asset: AVURLAsset!
	var videoMetadata: AVURLAsset.VideoMetadata!

	private var timeRange: ClosedRange<Double>?
	private var resizableDimensions: ResizableDimensions!
	private var predefinedSizes: [PredefinedSizeItem]!
	private let formatter = ByteCountFormatter()
	private var trimmingObserver: NSKeyValueObservation?

	private let tooltip = Tooltip(
		identifier: "savePanelArrowKeys",
		text: "Press the arrow up/down keys to change the value by 1. Hold the Option key meanwhile to change it by 10.",
		showOnlyOnce: true,
		maxWidth: 300
	)

	convenience init(inputUrl: URL, asset: AVURLAsset, videoMetadata: AVURLAsset.VideoMetadata) {
		self.init()

		self.inputUrl = inputUrl
		self.asset = asset
		self.videoMetadata = videoMetadata
	}

	@IBAction private func convert(_ sender: Any) {
		let conversion = Gifski.Conversion(
			video: inputUrl,
			timeRange: timeRange,
			quality: defaults[.outputQuality],
			dimensions: resizableDimensions.changed(dimensionsType: .pixels).currentDimensions.value,
			frameRate: frameRateSlider.integerValue
		)

		let convert = ConversionViewController(conversion: conversion)
		push(viewController: convert)
	}

	@IBAction private func cancel(_ sender: Any) {
		let videoDropController = VideoDropViewController()
		push(viewController: videoDropController)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		formatter.zeroPadsFractionDigits = true
		setUpDimensions()
		setUpDropdowns()
		setUpSliders()
		setUpWidthAndHeightTextFields()
		setUpDropView()
		setUpTrimmingView()
	}

	override func viewDidAppear() {
		super.viewDidAppear()

		dimensionsTypeDropdown.nextKeyView = frameRateSlider
		widthTextField.nextKeyView = heightTextField
		heightTextField.nextKeyView = dimensionsTypeDropdown

		tooltip.show(from: widthTextField, preferredEdge: .maxX)
		predefinedSizesDropdown.focus()
		playerView.hideTrimButtons()
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
				predefinedSizesDropdown.menu?.addItem(NSMenuItem.separator())
			case let .dimensions(dimensions):
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
			if let size = self.predefinedSizes?[safe: oldOrNewSelectedIndex], case .custom = size {
				// We don't care if it's newly selected index or not, if it's custom, set its size
				self.updateSelectedItemAsCustomWithSize()
			} else if let index = selectedIndex, let size = self.predefinedSizes?[safe: index],
				case .dimensions(let dimensions) = size {
				// But we care if it's newly selected index for dimensions, we don't want to recalculate
				// if we don't have to
				self.resizableDimensions.change(dimensionsType: dimensions.currentDimensions.type)
				self.resizableDimensions.resize(to: dimensions.currentDimensions.value)
				self.dimensionsUpdated()
			}
		}

		dimensionsTypeDropdown.removeAllItems()
		dimensionsTypeDropdown.addItems(withTitles: DimensionsType.allCases.map { $0.rawValue })

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
			self.estimateFileSize()
		}

		qualitySlider.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			defaults[.outputQuality] = self.qualitySlider.doubleValue
			self.estimateFileSize()
		}

		frameRateSlider.maxValue = videoMetadata.frameRate.clamped(to: 5...30)
		frameRateSlider.doubleValue = defaultFrameRate(inputFrameRate: videoMetadata.frameRate)
		frameRateSlider.triggerAction()

		qualitySlider.doubleValue = defaults[.outputQuality]
		qualitySlider.triggerAction()
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

	private func setUpDropView() {
		let videoDropController = VideoDropViewController(dropLabelIsHidden: true)
		add(childController: videoDropController)
	}

	private func setUpTrimmingView() {
		trimmingObserver = playerView.observe(\.canBeginTrimming, options: .new) { [weak self] _, change in
			if let canBeginTrimming = change.newValue, canBeginTrimming {
				self?.beginTrimming()
			}
		}
		playerView.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
	}

	private func beginTrimming() {
		playerView.beginTrimming(completionHandler: nil)
		playerView.observeTrimmedTimeRange { [weak self] timeRange in
			NSLog("startTime: \(timeRange.lowerBound), endTime: \(timeRange.upperBound)")
			self?.timeRange = timeRange
			self?.estimateFileSize()
		}
	}

	private func updateTextFieldsMinMax() {
		let widthMinMax = resizableDimensions.widthMinMax
		let heightMinMax = resizableDimensions.heightMinMax
		widthTextField.minMax = Int(widthMinMax.lowerBound)...Int(widthMinMax.upperBound)
		heightTextField.minMax = Int(heightMinMax.lowerBound)...Int(heightMinMax.upperBound)
	}

	private func dimensionsUpdated() {
		updateDimensionsDisplay()
		estimateFileSize()
		selectPredefinedSizeBasedOnCurrentDimensions()
	}

	private func estimateFileSize() {
		let duration: Double = {
			if let timeRange = self.timeRange {
				return timeRange.upperBound - timeRange.lowerBound
			} else {
				return videoMetadata.duration
			}
		}()
		let frameCount = duration * frameRateSlider.doubleValue
		let dimensions = resizableDimensions.changed(dimensionsType: .pixels).currentDimensions.value
		var fileSize = (Double(dimensions.width) * Double(dimensions.height) * frameCount) / 3
		fileSize = fileSize * (qualitySlider.doubleValue + 1.5) / 2.5
		estimatedSizeLabel.stringValue = "Estimated size: " + formatter.string(fromByteCount: Int64(fileSize))
	}

	private func updateDimensionsDisplay() {
		widthTextField.stringValue = String(format: "%.0f", resizableDimensions.currentDimensions.value.width)
		heightTextField.stringValue = String(format: "%.0f", resizableDimensions.currentDimensions.value.height)
		dimensionsTypeDropdown.selectItem(withTitle: resizableDimensions.currentDimensions.type.rawValue)
	}

	private func selectPredefinedSizeBasedOnCurrentDimensions() {
		// First reset the state
		predefinedSizesDropdown.selectItem(at: NSNotFound)

		// Check if we can select predefined option that has the same dimensions settings
		if let index = predefinedSizes.firstIndex(where: { $0.resizableDimensions?.currentDimensions == resizableDimensions.currentDimensions }) {
			predefinedSizesDropdown.selectItem(at: index)
		} else {
			updateSelectedItemAsCustomWithSize()
		}
	}

	private func updateSelectedItemAsCustomWithSize() {
		let newType: DimensionsType = resizableDimensions.currentDimensions.type == .percent ? .pixels : .percent
		let resizableDimensions = self.resizableDimensions.changed(dimensionsType: newType)
		let selectedCustomTitle = "Custom - \(resizableDimensions.currentDimensions)"
		predefinedSizesDropdown.item(at: 0)?.title = selectedCustomTitle
		predefinedSizesDropdown.selectItem(at: 0)
	}

	private func defaultFrameRate(inputFrameRate frameRate: Double) -> Double {
		let defaultFrameRate = frameRate >= 24 ? frameRate / 2 : frameRate
		return defaultFrameRate.clamped(to: 5...30)
	}
}
