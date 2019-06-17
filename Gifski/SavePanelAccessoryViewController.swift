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

	@IBOutlet private var widthTextField: NSTextField!
	@IBOutlet private var heightTextField: NSTextField!
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

		widthTextField.delegate = self
		heightTextField.delegate = self

		// Set initial defaults
		configureFramerateSlider(inputFrameRate: videoMetadata.frameRate)
		configureQualitySlider()
	}

	private func dimensionsUpdated() {
		updateDimensionsDisplay()
		estimateFileSize()
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

	private func configureFramerateSlider(inputFrameRate frameRate: Double) {
		frameRateSlider.maxValue = frameRate.clamped(to: 5...30)
		frameRateSlider.doubleValue = defaultFrameRate(inputFrameRate: frameRate)
		frameRateSlider.triggerAction()
	}

	private func defaultFrameRate(inputFrameRate frameRate: Double) -> Double {
		let defaultFrameRate = frameRate >= 24 ? frameRate / 2 : frameRate
		return defaultFrameRate.clamped(to: 5...30)
	}

	private func configureQualitySlider() {
		qualitySlider.doubleValue = defaults[.outputQuality]
		qualitySlider.triggerAction()
	}

	private func scalingTextFieldTextDidChange(_ textField: NSTextField) {
		let valid: Bool
		if textField == widthTextField {
			let width = CGFloat(Double(self.widthTextField.stringValue) ?? 0.0)
			valid = resizableDimensions.validate(newWidth: width)
			resizableDimensions.resize(usingWidth: width)
		} else if textField == heightTextField {
			let height = CGFloat(Double(self.heightTextField.stringValue) ?? 0.0)
			valid = resizableDimensions.validate(newHeight: height)
			resizableDimensions.resize(usingHeight: height)
		} else {
			return
		}

		if !valid {
			textField.shake(direction: .horizontal)
		}
		dimensionsUpdated()
		predefinedSizesDropdown.selectItem(at: 0)
	}
}

extension SavePanelAccessoryViewController: NSTextFieldDelegate {
	func controlTextDidChange(_ obj: Notification) {
		guard let textField = obj.object as? NSTextField else {
			return
		}
		scalingTextFieldTextDidChange(textField)
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		guard let currentValue = Int(textView.string) else {
			return false
		}

		let deltaValue: Int
		switch commandSelector {
		case #selector(moveUp):
			deltaValue = 1
		case #selector(moveDown):
			deltaValue = -1
		case #selector(moveBackward):
			deltaValue = 10
		case #selector(moveForward):
			deltaValue = -10
		default:
			// we only handle arrow-up (moveUp), arrow-down (moveDown), option+arrow-up (moveBackward), option+arrow-down (moveForward)
			return false
		}

		textView.string = "\(currentValue + deltaValue)"
		if let correspondingTextField = textView.superview?.superview as? NSTextField {
			scalingTextFieldTextDidChange(correspondingTextField)
		}
		return true
	}
}
