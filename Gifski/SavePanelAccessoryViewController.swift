import Cocoa

final class SavePanelAccessoryViewController: NSViewController {
	@IBOutlet private var estimatedSizeLabel: NSTextField!
	@IBOutlet private var scaleSlider: NSSlider!
	@IBOutlet private var scaleLabel: NSTextField!
	@IBOutlet private var frameRateSlider: NSSlider!
	@IBOutlet private var frameRateLabel: NSTextField!
	@IBOutlet private var qualitySlider: NSSlider!
	var inputUrl: URL!
	var onDimensionChange: ((CGSize) -> Void)?
	var onFramerateChange: ((Int) -> Void)?

	override func viewDidLoad() {
		super.viewDidLoad()

		let formatter = ByteCountFormatter()
		formatter.zeroPadsFractionDigits = true

		// TODO: Use KVO here

		let metadata = inputUrl.videoMetadata!
		var currentDimensions = metadata.dimensions

		func estimateFileSize() {
			let frameCount = metadata.duration * frameRateSlider.doubleValue
			var fileSize = (Double(currentDimensions.width) * Double(currentDimensions.height) * frameCount) / 3
			fileSize = fileSize * (qualitySlider.doubleValue + 1.5) / 2.5
			estimatedSizeLabel.stringValue = formatter.string(fromByteCount: Int64(fileSize))
		}

		scaleSlider.onAction = { _ in
			currentDimensions = metadata.dimensions * self.scaleSlider.doubleValue
			self.scaleLabel.stringValue = "\(Int(currentDimensions.width))×\(Int(currentDimensions.height))"
			estimateFileSize()
			self.onDimensionChange?(currentDimensions)
		}

		frameRateSlider.onAction = { _ in
			let frameRate = self.frameRateSlider.integerValue
			self.frameRateLabel.stringValue = "\(frameRate)"
			self.onFramerateChange?(frameRate)
			estimateFileSize()
		}

		qualitySlider.onAction = { _ in
			defaults[.outputQuality] = self.qualitySlider.doubleValue
			estimateFileSize()
		}

		// Set initial defaults
		configureScaleSlider(inputDimensions: metadata.dimensions)
		configureFramerateSlider(inputFrameRate: metadata.frameRate)
		configureQualitySlider()
	}

	private func configureScaleSlider(inputDimensions dimensions: CGSize) {
		if dimensions.width >= 640 {
			scaleSlider.doubleValue = 0.5
		}
		scaleSlider.minValue = minimumScale(inputDimensions: dimensions)
		scaleSlider.triggerAction()
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
