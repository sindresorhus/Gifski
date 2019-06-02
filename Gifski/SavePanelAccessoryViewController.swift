import Cocoa
import AVKit

final class SavePanelAccessoryViewController: NSViewController, NSTextFieldDelegate {
	@IBOutlet private var estimatedSizeLabel: NSTextField!
	@IBOutlet private var frameRateSlider: NSSlider!
	@IBOutlet private var frameRateLabel: NSTextField!
	@IBOutlet private var qualitySlider: NSSlider!

	@IBOutlet private var predefinedSizesDropdown: NSPopUpButton!
	@IBOutlet private var widthTextField: NSTextField!
	@IBOutlet private var heightTextField: NSTextField!
	@IBOutlet private var widthHeightTypeDropdown: NSPopUpButton!
	@IBOutlet private var proportionalScaleAffordanceButton: NSButton!

	var inputUrl: URL!
	var videoMetadata: AVURLAsset.VideoMetadata!
	var onDimensionChange: ((CGSize) -> Void)?
	var onFramerateChange: ((Int) -> Void)?
	var fileDimensions = CGSize(width: 0, height: 0)
	var currentDimensions = CGSize(width: 0, height: 0)
	var shouldRevertX = false
	var shouldRevertY = false

	let formatter = ByteCountFormatter()

	private var dimensionRatios: [Float] = [1.0, 1.0]
	private var scaleXDoubleValue: Double = 1.0
	private var scaleYDoubleValue: Double = 1.0
	private var scaleXMinDoubleValue: Double = 0.0
	private var scaleYMinDoubleValue: Double = 0.0

	override func viewDidLoad() {
		super.viewDidLoad()
		formatter.zeroPadsFractionDigits = true

		/// TODO: Use KVO here
		videoMetadata = inputUrl.videoMetadata!
		fileDimensions = videoMetadata.dimensions

		frameRateSlider.onAction = { _ in
			let frameRate = self.frameRateSlider.integerValue
			self.frameRateLabel.stringValue = "\(frameRate)"
			self.onFramerateChange?(frameRate)
			self.estimateFileSize()
		}

		qualitySlider.onAction = { _ in
			defaults[.outputQuality] = self.qualitySlider.doubleValue
			self.estimateFileSize()
		}

		predefinedSizesDropdown.onAction = {_ in
			if let item = self.predefinedSizesDropdown.selectedItem {
				let index = self.predefinedSizesDropdown.index(of: item)
				let correspondingScale = self.dimensionRatios[index]
				self.scaleXDoubleValue = Double(correspondingScale)
				self.scaleYDoubleValue = Double(correspondingScale)
				self.widthTextField.stringValue = "\(Int(Double(self.fileDimensions.width) * self.scaleXDoubleValue))"
				self.heightTextField.stringValue = "\(Int(Double(self.fileDimensions.height) * self.scaleYDoubleValue))"
			}
			self.recalculateCurrentDimensions()
		}

		widthHeightTypeDropdown.onAction = {_ in
			if let item = self.widthHeightTypeDropdown.selectedItem {
				let index = self.widthHeightTypeDropdown.index(of: item)
				if index == 0 {
					self.updateTextFieldsFromPopup(asPercentage: false)
				} else {
					self.updateTextFieldsFromPopup(asPercentage: true)
				}
			}
		}

		widthTextField.delegate = self
		heightTextField.delegate = self

		// Set initial defaults
		configureScaleSettings(inputDimensions: videoMetadata.dimensions)
		configureFramerateSlider(inputFrameRate: videoMetadata.frameRate)
		configureQualitySlider()
	}

	private var percentageMode: Bool {
		guard let item = self.widthHeightTypeDropdown.selectedItem else {
			return false
		}
		let index = self.widthHeightTypeDropdown.index(of: item)
		if index == 1 {
			return true
		} else {
			return false
		}
	}

	func estimateFileSize() {
		let frameCount = videoMetadata.duration * frameRateSlider.doubleValue
		var fileSize = (Double(currentDimensions.width) * Double(currentDimensions.height) * frameCount) / 3
		fileSize = fileSize * (qualitySlider.doubleValue + 1.5) / 2.5
		estimatedSizeLabel.stringValue = "Estimated size: " + formatter.string(fromByteCount: Int64(fileSize))
	}

	func recalculateCurrentDimensions() {
		self.currentDimensions = CGSize(width: fileDimensions.width * CGFloat(scaleXDoubleValue), height: fileDimensions.height * CGFloat(scaleYDoubleValue))
		estimateFileSize()
		self.onDimensionChange?(self.currentDimensions)
	}

	func controlTextDidChange(_ obj: Notification) {
		guard let textField = obj.object as? NSTextField else {
			return
		}
		scalingTextFieldTextDidChange(textField)
	}

	func scalingTextFieldTextDidChange(_ textField: NSTextField) {
		if textField == widthTextField {
			guard let width = Double(self.widthTextField.stringValue) else {
				return
			}
			var currentScaleXDoubleValue: Double = 0
			if percentageMode {
				currentScaleXDoubleValue = width / 100
			} else {
				currentScaleXDoubleValue = width / Double(fileDimensions.width)
			}
			if !validateScaleDoubleValue(currentScaleXDoubleValue, pendingX: false, pendingY: true) {
				return
			}
			self.scaleXDoubleValue = currentScaleXDoubleValue
			self.predefinedSizesDropdown.selectItem(at: 0)
			self.scaleYDoubleValue = self.scaleXDoubleValue
			if percentageMode {
				self.heightTextField.stringValue = "\(Int(100 * CGFloat(scaleYDoubleValue)))"
			} else {
				self.heightTextField.stringValue = "\(Int(Double(fileDimensions.height) * self.scaleYDoubleValue))"
			}
			self.recalculateCurrentDimensions()
		} else if textField == heightTextField {
			guard let height = Double(self.heightTextField.stringValue) else {
				return
			}
			var currentScaleYDoubleValue: Double = 0
			if percentageMode {
				currentScaleYDoubleValue = height / 100
			} else {
				currentScaleYDoubleValue = height / Double(fileDimensions.height)
			}
			if !validateScaleDoubleValue(currentScaleYDoubleValue, pendingX: false, pendingY: true) {
				return
			}
			self.scaleYDoubleValue = currentScaleYDoubleValue
			self.predefinedSizesDropdown.selectItem(at: 0)
			self.scaleXDoubleValue = self.scaleYDoubleValue
			if percentageMode {
				self.widthTextField.stringValue = "\(Int(100 * CGFloat(scaleXDoubleValue)))"
			} else {
				self.widthTextField.stringValue = "\(Int(Double(fileDimensions.width) * self.scaleXDoubleValue))"
			}
			self.recalculateCurrentDimensions()
		}
	}

	private func validateScaleDoubleValue(_ scaleValue: Double, pendingX: Bool, pendingY: Bool) -> Bool {
		if scaleValue <= 0.001 || scaleValue > 1 {
			return false
		} else {
			return true
		}
	}

	private func configureScaleSettings(inputDimensions dimensions: CGSize) {
		for divisor in 1..<6 {
			let divisorFloat = CGFloat(integerLiteral: divisor)
			let dimensionRatio = Float(1 / divisorFloat)
			dimensionRatios.append(dimensionRatio)
			var percentageString: String = "Original"
			if divisor != 1 {
				percentageString = "\(Int(round(dimensionRatio * 100.0)))%"
			}
			predefinedSizesDropdown.addItem(withTitle: " \(Int(dimensions.width / divisorFloat)) × \(Int(dimensions.height / divisorFloat)) (\(percentageString))")
		}
		predefinedSizesDropdown.menu?.addItem(NSMenuItem.separator())
		dimensionRatios.append(1)
		let commonsizes = [960, 800, 640, 500, 480, 320, 256, 200, 160, 128, 80, 64]
		for size in commonsizes {
			let dimensionRatio = CGFloat(size) / dimensions.width
			dimensionRatios.append(Float(dimensionRatio))
			let percentageString = "\(Int(round(dimensionRatio * 100.0)))%"
			predefinedSizesDropdown.addItem(withTitle: "\(Int(dimensions.width * dimensionRatio)) × \(Int(dimensions.height * dimensionRatio)) (\(percentageString))")
		}
		if dimensions.width >= 640 {
			scaleXDoubleValue = 0.5
			scaleYDoubleValue = 0.5
			predefinedSizesDropdown.selectItem(at: 3)
		} else {
			predefinedSizesDropdown.selectItem(at: 2)
		}
		scaleXMinDoubleValue = minimumScale(inputDimensions: dimensions)
		scaleYMinDoubleValue = scaleXMinDoubleValue
		updateTextFieldsFromPopup(asPercentage: false)
		self.recalculateCurrentDimensions()
	}

	private func updateTextFieldsFromPopup(asPercentage: Bool) {
		if asPercentage {
			widthTextField.stringValue = "\(Int(100 * CGFloat(scaleXDoubleValue)))"
			heightTextField.stringValue = "\(Int(100 * CGFloat(scaleYDoubleValue)))"
		} else {
			widthTextField.stringValue = "\(Int(videoMetadata.dimensions.width * CGFloat(scaleXDoubleValue)))"
			heightTextField.stringValue = "\(Int(videoMetadata.dimensions.height * CGFloat(scaleYDoubleValue)))"
		}
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		var deltaValue = 0
		if commandSelector == #selector(moveUp(_:)) {
			deltaValue = 1
		} else if commandSelector == #selector(moveDown(_:)) {
			deltaValue = -1
		} else {
			return false
		}
		guard let currentValue = Int(textView.string) else {
			return false
		}
		textView.string = "\(currentValue + deltaValue)"
		if let correspondingTextField = textView.superview?.superview as? NSTextField {
			scalingTextFieldTextDidChange(correspondingTextField)
		}
		return true
	}

	private func minimumScale(inputDimensions dimensions: CGSize) -> Double {
		let shortestSide = min(dimensions.width, dimensions.height)
		return 10 / Double(shortestSide)
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
}
