import Cocoa
import AVFoundation

final class SavePanelAccessoryViewController: NSViewController {
	@IBOutlet private weak var estimatedSizeLabel: NSTextField!
	@IBOutlet private weak var scaleSlider: NSSlider!
	@IBOutlet private weak var scaleLabel: NSTextField!
	@IBOutlet private weak var frameRateSlider: NSSlider!
	@IBOutlet private weak var frameRateLabel: NSTextField!
	@IBOutlet private weak var qualitySlider: NSSlider!
	var inputUrl: URL!
	var onDimensionChange: ((CGSize) -> Void)?
	var onFramerateChange: ((Int) -> Void)?

	var metadata: AVURLAsset.VideoMetadata {
		return inputUrl.videoMetadata!
	}

	var frameRate: Int {
		return Int(metadata.frameRate)
	}

	var maxFrameRate: Double {
		return Double(frameRate.clamped(to: 5...30))
	}

	var defaultFrameRate: Int {
		let defaultFrameRate = frameRate < 24 ? frameRate : frameRate / 2
		return defaultFrameRate.clamped(to: 5...30)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		/// TODO: Find a way to create a `NSTextField` extension that adheres to `NSAppearance.app`
		view.invertTextColorOnTextFieldsIfDark()

		let formatter = ByteCountFormatter()
		formatter.zeroPadsFractionDigits = true

		/// TODO: Use KVO here
		var currentDimensions = metadata.dimensions

		func estimateFileSize() {
			let frameCount = metadata.duration * frameRateSlider.doubleValue
			var fileSize = (Double(currentDimensions.width) * Double(currentDimensions.height) * frameCount) / 3
			fileSize = fileSize * (qualitySlider.doubleValue + 1.5) / 2.5
			estimatedSizeLabel.stringValue = formatter.string(fromByteCount: Int64(fileSize))
		}

		scaleSlider.onAction = { _ in
			currentDimensions = self.metadata.dimensions * self.scaleSlider.doubleValue
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
		if metadata.dimensions.width >= 640 {
			scaleSlider.doubleValue = 0.5
		}
		scaleSlider.triggerAction()
		frameRateSlider.maxValue = maxFrameRate
		frameRateSlider.integerValue = defaultFrameRate
		frameRateSlider.triggerAction()
		qualitySlider.doubleValue = defaults[.outputQuality]
		qualitySlider.triggerAction()
	}
}
