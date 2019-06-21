import Cocoa
import AVKit

final class SavePanelAccessoryViewController: NSViewController {
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

	var inputUrl: URL!
	var videoMetadata: AVURLAsset.VideoMetadata!
	var onDimensionChange: ((CGSize) -> Void)?
	var onFramerateChange: ((Int) -> Void)?

	let formatter = ByteCountFormatter()

	private var resizableDimensions: ResizableDimensions!
	private var predefinedSizes: [PredefinedSizeItem]!

	override func viewDidLoad() {
		super.viewDidLoad()

		formatter.zeroPadsFractionDigits = true
		setupDimensions()
		setupDropdowns()
		setupSliders()
		setupWidthAndHeightTextFields()
	}

	override func viewWillAppear() {
		super.viewWillAppear()

		// Hack to enlarge extended save panel frame. Original frame: {841,481}
		UserDefaults.standard.set("{841, 681}", forKey: "NSNavPanelExpandedSizeForSaveMode")
	}

	override func viewDidAppear() {
		super.viewDidAppear()

		dimensionsTypeDropdown.nextKeyView = heightTextField.nextKeyView
		widthTextField.nextKeyView = heightTextField
		heightTextField.nextKeyView = dimensionsTypeDropdown

		if !defaults[.tooltipCmdArrowsShown] {
			defaults[.tooltipCmdArrowsShown] = true
			let tooltip = Tooltip(text: "You can also navigate using arrows. Hold CMD and you can navigate even faster!", contentInsets: .init(value: 6.0), maxWidth: 250.0)
			tooltip.show(relativeTo: widthTextField.bounds, of: widthTextField, preferredEdge: .maxX)
		}
	}

	private func setupDimensions() {
		let minimumScale: CGFloat = 0.01
		let maximumScale: CGFloat = 1.0
		let dimensions = Dimensions(type: .pixels, value: videoMetadata.dimensions)
		resizableDimensions = ResizableDimensions(dimensions: dimensions, minimumScale: minimumScale, maximumScale: maximumScale)

		var pixelCommonSizes: [CGFloat] = [960.0, 800.0, 640.0, 500.0, 480.0, 320.0, 256.0, 200.0, 160.0, 128.0, 80.0, 64.0]
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

		let percentCommonSizes: [CGFloat] = [50.0, 33.0, 25.0, 20.0]
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

	private func setupDropdowns() {
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

		predefinedSizesDropdown.onMenuWillOpenAction = { [weak self] in
			self?.predefinedSizesDropdown.item(at: 0)?.title = "Custom"
		}
		predefinedSizesDropdown.onMenuDidCloseAction = { [weak self] selectedIndex in
			guard let self = self else {
				return
			}

			let oldOrNewSelectedIndex = selectedIndex ?? self.predefinedSizesDropdown.indexOfSelectedItem
			if let size = self.predefinedSizes?[safe: oldOrNewSelectedIndex], case .custom = size {
				// we don't care if it's newly selected index or not - if it's custom, set its size
				self.updateSelectedItemAsCustomWithSize()
			} else if let index = selectedIndex, let size = self.predefinedSizes?[safe: index],
				case .dimensions(let dimensions) = size {
				// but we care if it's newly selected index for dimensions, we don't want to recalculate
				// if we don't have to
				self.resizableDimensions.change(dimensionsType: dimensions.currentDimensions.type)
				self.resizableDimensions.resize(to: dimensions.currentDimensions.value)
				self.dimensionsUpdated()
			}
		}

		dimensionsTypeDropdown.removeAllItems()
		dimensionsTypeDropdown.addItems(withTitles: DimensionsType.allCases.map { $0.rawValue })

		dimensionsTypeDropdown.onMenuDidCloseAction = { [weak self] selectedIndex in
			guard let self = self, let index = selectedIndex, let item = self.dimensionsTypeDropdown.item(at: index),
				let dimensionsType = DimensionsType(rawValue: item.title) else {
				return
			}

			self.resizableDimensions.change(dimensionsType: dimensionsType)
			self.dimensionsUpdated()
			self.updateTextFieldsMinMax()
		}

		if resizableDimensions.currentDimensions.value.width > 640.0 {
			predefinedSizesDropdown.selectItem(at: 3)
		} else {
			predefinedSizesDropdown.selectItem(at: 2)
		}
		dimensionsUpdated()
	}

	private func setupSliders() {
		frameRateSlider.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			let frameRate = self.frameRateSlider.integerValue
			self.frameRateLabel.stringValue = "\(frameRate)"
			self.onFramerateChange?(frameRate)
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

	private func setupWidthAndHeightTextFields() {
		widthTextField.onBlur = { [weak self] width in
			self?.resizableDimensions.resize(usingWidth: CGFloat(width))
			self?.dimensionsUpdated()
		}
		widthTextField.onValidValueChange = { [weak self] width in
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
		heightTextField.onValidValueChange = { [weak self] height in
			guard let self = self else {
				return
			}

			self.resizableDimensions.resize(usingHeight: CGFloat(height))
			self.dimensionsUpdated()
		}
		updateTextFieldsMinMax()
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
		onDimensionChange?(resizableDimensions.currentDimensions.value)
	}

	private func estimateFileSize() {
		let frameCount = videoMetadata.duration * frameRateSlider.doubleValue
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
