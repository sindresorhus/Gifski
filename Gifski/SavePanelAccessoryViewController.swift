import Cocoa

final class SavePanelAccessoryViewController: NSViewController {
	@IBOutlet private weak var dimensionsSlider: NSSlider!
	@IBOutlet private weak var dimensionsLabel: NSTextField!
	@IBOutlet private weak var qualitySlider: NSSlider!
	@IBOutlet private weak var estimatedSizeLabel: NSTextField!
	var inputUrl: URL!

	override func viewDidLoad() {
		super.viewDidLoad()

		view.autoresizingMask = [.minXMargin, .maxXMargin]

		let formatter = ByteCountFormatter()
		formatter.zeroPadsFractionDigits = true

		/// TODO: Use KVO here

		let metadata = inputUrl.videoMetadata!
		let FPS = 24.0
		let frameCount = metadata.duration * FPS
		var currentDimensions = metadata.dimensions

		func estimateFileSize() {
			var fileSize = (Double(currentDimensions.width) * Double(currentDimensions.height) * Double(frameCount)) / 3
			fileSize = fileSize * (qualitySlider.doubleValue + 1.5) / 2.5
			estimatedSizeLabel.stringValue = formatter.string(fromByteCount: Int64(fileSize))
		}

		dimensionsSlider.onAction = { _ in
			currentDimensions = metadata.dimensions * self.dimensionsSlider.doubleValue
			self.dimensionsLabel.stringValue = "\(Int(currentDimensions.width))×\(Int(currentDimensions.height))"
			estimateFileSize()

			/// TODO: Feels hacky to do it this way. Find a better way to pass the state.
			self.appDelegate.choosenDimensions = currentDimensions
		}

		qualitySlider.onAction = { _ in
			defaults["outputQuality"] = self.qualitySlider.doubleValue
			estimateFileSize()
		}

		// Set initial defaults
		dimensionsSlider.triggerAction()
		qualitySlider.doubleValue = defaults["outputQuality"] as! Double
	}
}
