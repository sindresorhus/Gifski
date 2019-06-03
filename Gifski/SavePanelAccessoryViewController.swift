import Cocoa
import AVKit

final class SavePanelAccessoryViewController: NSViewController {
	@IBOutlet private var estimatedSizeLabel: NSTextField!
	@IBOutlet private var frameRateSlider: NSSlider!
	@IBOutlet private var frameRateLabel: NSTextField!
	@IBOutlet private var qualitySlider: NSSlider!

	@IBOutlet private var widthTextField: NSTextField!
	@IBOutlet private var heightTextField: NSTextField!
	@IBOutlet private var predefinedSizesDropdown: NSPopUpButton!
	@IBOutlet private var dimensionsModeDropdown: NSPopUpButton!

	var inputUrl: URL!
	var videoMetadata: AVURLAsset.VideoMetadata!
	var onDimensionChange: ((CGSize) -> Void)?
	var onFramerateChange: ((Int) -> Void)?

	let formatter = ByteCountFormatter()

	private var dimensionsMode = DimensionsMode.pixels {
		didSet {
			self.currentScale = self.dimensionsMode.validated(widthScale: self.currentScale, originalSize: self.fileDimensions)
		}
	}
	private var dimensionRatios: [Double] = [1.0, 1.0]

	private var currentScale: Double = 1.0 {
		didSet {
			dimensionsUpdated()
		}
	}

	private var fileDimensions: CGSize {
		return videoMetadata.dimensions
	}

	private var currentDimensions: CGSize {
		let width = dimensionsMode.width(fromScale: currentScale, originalSize: fileDimensions)
		let height = dimensionsMode.height(fromScale: currentScale, originalSize: fileDimensions)
		return CGSize(width: width, height: height)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		formatter.zeroPadsFractionDigits = true

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

		predefinedSizesDropdown.onAction = { [weak self] _ in
			guard let self = self, let item = self.predefinedSizesDropdown.selectedItem else {
				return
			}

			let index = self.predefinedSizesDropdown.index(of: item)
			self.currentScale = self.dimensionRatios[index]
		}

		dimensionsModeDropdown.removeAllItems()
		dimensionsModeDropdown.addItems(withTitles: DimensionsMode.allCases.map { $0.title })

		dimensionsModeDropdown.onAction = { [weak self] _ in
			guard let self = self, let item = self.dimensionsModeDropdown.selectedItem else {
				return
			}
			self.dimensionsMode = DimensionsMode(title: item.title)
		}

		widthTextField.delegate = self
		heightTextField.delegate = self

		// Set initial defaults
		configureScaleSettings(inputDimensions: videoMetadata.dimensions)
		configureFramerateSlider(inputFrameRate: videoMetadata.frameRate)
		configureQualitySlider()
	}

	private func dimensionsUpdated() {
		updateWidthAndHeight()
		estimateFileSize()
		onDimensionChange?(currentDimensions)
	}

	private func estimateFileSize() {
		let frameCount = videoMetadata.duration * frameRateSlider.doubleValue
		var fileSize = (Double(currentDimensions.width) * Double(currentDimensions.height) * frameCount) / 3
		fileSize = fileSize * (qualitySlider.doubleValue + 1.5) / 2.5
		estimatedSizeLabel.stringValue = "Estimated size: " + formatter.string(fromByteCount: Int64(fileSize))
	}

	// TODO: clean this up
	private func configureScaleSettings(inputDimensions dimensions: CGSize) {
		for divisor in 1..<6 {
			let divisorFloat = CGFloat(integerLiteral: divisor)
			let dimensionRatio = Double(1.0 / divisorFloat)
			dimensionRatios.append(dimensionRatio)
			var percentString: String = "Original"
			if divisor != 1 {
				percentString = "\(Int(round(dimensionRatio * 100.0)))%"
			}
			predefinedSizesDropdown.addItem(withTitle: " \(Int(dimensions.width / divisorFloat)) × \(Int(dimensions.height / divisorFloat)) (\(percentString))")
		}
		predefinedSizesDropdown.menu?.addItem(NSMenuItem.separator())
		dimensionRatios.append(1)
		let commonsizes = [960, 800, 640, 500, 480, 320, 256, 200, 160, 128, 80, 64]
		for size in commonsizes {
			let dimensionRatio = CGFloat(size) / dimensions.width
			dimensionRatios.append(Double(dimensionRatio))
			let percentString = "\(Int(round(dimensionRatio * 100.0)))%"
			predefinedSizesDropdown.addItem(withTitle: "\(Int(dimensions.width * dimensionRatio)) × \(Int(dimensions.height * dimensionRatio)) (\(percentString))")
		}
		if dimensions.width >= 640 {
			currentScale = 0.5
			predefinedSizesDropdown.selectItem(at: 3)
		} else {
			predefinedSizesDropdown.selectItem(at: 2)
		}
	}

	private func updateWidthAndHeight() {
		widthTextField.stringValue = "\(Int(currentDimensions.width))"
		heightTextField.stringValue = "\(Int(currentDimensions.height))"
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
		let userScale: Double
		let validatedScale: Double

		if textField == widthTextField, let width = Double(self.widthTextField.stringValue) {
			userScale = dimensionsMode.scale(width: width, originalSize: fileDimensions)
			validatedScale = dimensionsMode.validated(widthScale: userScale, originalSize: fileDimensions)
			// TODO: edge case (preview doesn't handle it either)
			// when the aspect ratio for the image is big, specyfing width 1 will make height 0
		} else if textField == heightTextField, let height = Double(self.heightTextField.stringValue) {
			userScale = dimensionsMode.scale(width: height, originalSize: fileDimensions)
			validatedScale = dimensionsMode.validated(heightScale: userScale, originalSize: fileDimensions)
		} else {
			return
		}

		if !userScale.isEqual(to: validatedScale) {
			textField.shake()
		}

		self.currentScale = validatedScale
		self.predefinedSizesDropdown.selectItem(at: 0)
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
			deltaValue = dimensionsMode.deltaUnit
		case #selector(moveDown):
			deltaValue = dimensionsMode.deltaUnit * -1
		case #selector(moveBackward):
			deltaValue = dimensionsMode.biggerDeltaUnit
		case #selector(moveForward):
			deltaValue = dimensionsMode.biggerDeltaUnit * -1
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
