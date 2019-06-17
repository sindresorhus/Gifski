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
	@IBOutlet private var predefinedSizesDropdown: NSPopUpButton!
	@IBOutlet private var dimensionsTypeDropdown: NSPopUpButton!

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

	private func setupDimensions() {
		let minimumScale: CGFloat = 0.01
		let maximumScale: CGFloat = 1.0
		let dimensions = Dimensions(type: .pixels, value: videoMetadata.dimensions)
		resizableDimensions = ResizableDimensions(dimensions: dimensions, minimumScale: minimumScale, maximumScale: maximumScale)

		let pixelCommonSizes: [CGFloat] = [dimensions.value.width, 960.0, 800.0, 640.0, 500.0, 480.0, 320.0, 256.0, 200.0, 160.0, 128.0, 80.0, 64.0].sorted(by: >)
		let pixelDimensions = pixelCommonSizes.map { width -> CGSize in
			let ratio = width / dimensions.value.width
			let height = dimensions.value.height * ratio
			return CGSize(width: width, height: height)
		}
		let predefinedPixelDimensions = pixelDimensions
			.filter { resizableDimensions.validate(newSize: $0) }
			.map { resizableDimensions.resized(to: $0) }

		let percentCommonSizes: [CGFloat] = [100.0, 50.0, 33.0, 25.0, 20.0]
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

		predefinedSizesDropdown.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			let index = self.predefinedSizesDropdown.indexOfSelectedItem
			if let size = self.predefinedSizes?[safe: index], case .dimensions(let dimensions) = size {
				self.resizableDimensions.change(dimensionsType: dimensions.currentDimensions.type)
				self.resizableDimensions.resize(to: dimensions.currentDimensions.value)
				self.dimensionsUpdated()
			}
		}

		dimensionsTypeDropdown.removeAllItems()
		dimensionsTypeDropdown.addItems(withTitles: DimensionsType.allCases.map { $0.rawValue })

		dimensionsTypeDropdown.onAction = { [weak self] _ in
			guard let self = self, let item = self.dimensionsTypeDropdown.selectedItem,
				let dimensionsType = DimensionsType(rawValue: item.title) else {
				return
			}

			self.resizableDimensions.change(dimensionsType: dimensionsType)
			self.dimensionsUpdated()
		}

		if resizableDimensions.currentDimensions.value.width > 640.0 {
			predefinedSizesDropdown.selectItem(at: 3)
		} else {
			predefinedSizesDropdown.selectItem(at: 2)
		}
		predefinedSizesDropdown.onAction?(predefinedSizesDropdown)
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
		widthTextField.onTextDidChange = { [weak self] width in
			guard let self = self else {
				return
			}

			if self.resizableDimensions.validate(newWidth: CGFloat(width)) {
				self.resizableDimensions.resize(usingWidth: CGFloat(width))
				self.dimensionsUpdated()
			} else {
				self.widthTextField.shake(direction: .horizontal)
			}
		}
		heightTextField.onBlur = { [weak self] height in
			self?.resizableDimensions.resize(usingHeight: CGFloat(height))
			self?.dimensionsUpdated()
		}
		heightTextField.onTextDidChange = { [weak self] height in
			guard let self = self else {
				return
			}

			if self.resizableDimensions.validate(newHeight: CGFloat(height)) {
				self.resizableDimensions.resize(usingHeight: CGFloat(height))
				self.dimensionsUpdated()
			} else {
				self.heightTextField.shake(direction: .horizontal)
			}
		}
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
		// Check if we can select predefined option that has the same dimensions settings
		if let index = predefinedSizes.firstIndex(where: { $0.resizableDimensions?.currentDimensions == resizableDimensions.currentDimensions }) {
			predefinedSizesDropdown.selectItem(at: index)
		} else {
			// If we can't, change dimension type and try again
			let newType: DimensionsType = resizableDimensions.currentDimensions.type == .percent ? .pixels : .percent
			let resizableDimensions = self.resizableDimensions.changed(dimensionsType: newType)
			if let index = predefinedSizes.firstIndex(where: { $0.resizableDimensions?.currentDimensions == resizableDimensions.currentDimensions }) {
				predefinedSizesDropdown.selectItem(at: index)
			} else {
				// If all fails, select custom and assign a custom pixels label to it
				predefinedSizesDropdown.selectItem(at: 0)
				let selectedCustomTitle = "Custom - \(resizableDimensions)"
			}
		}
	}

	private func defaultFrameRate(inputFrameRate frameRate: Double) -> Double {
		let defaultFrameRate = frameRate >= 24 ? frameRate / 2 : frameRate
		return defaultFrameRate.clamped(to: 5...30)
	}
}
