import Cocoa

final class SavePanelAccessoryViewController: NSViewController {
	@IBOutlet private weak var estimatedSizeLabel: NSTextField!
	@IBOutlet private weak var scaleSlider: NSSlider!
	@IBOutlet private weak var scaleLabel: NSTextField!
	@IBOutlet private weak var frameRateSlider: NSSlider!
	@IBOutlet private weak var frameRateLabel: NSTextField!
	@IBOutlet private weak var qualitySlider: NSSlider!
	var inputUrl: URL!

	override func viewDidLoad() {
		super.viewDidLoad()

		let formatter = ByteCountFormatter()
		formatter.zeroPadsFractionDigits = true

		/// TODO: Use KVO here

		let metadata = inputUrl.videoMetadata!
		let frameRate = Int(metadata.frameRate).clamped(to: 5...30)
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

			/// TODO: Feels hacky to do it this way. Find a better way to pass the state.
			self.appDelegate.choosenDimensions = currentDimensions
		}

		frameRateSlider.onAction = { _ in
			let frameRate = self.frameRateSlider.integerValue
			self.frameRateLabel.stringValue = "\(frameRate)"
			self.appDelegate.choosenFrameRate = frameRate
			estimateFileSize()
		}

		qualitySlider.onAction = { _ in
			defaults["outputQuality"] = self.qualitySlider.doubleValue
			estimateFileSize()
		}

		// Set initial defaults
		scaleSlider.triggerAction()
		frameRateSlider.maxValue = Double(frameRate)
		frameRateSlider.integerValue = frameRate
		frameRateSlider.triggerAction()
		qualitySlider.doubleValue = defaults["outputQuality"] as! Double
		qualitySlider.triggerAction()
	}
}
