import Cocoa
import ProgressKit
import DockProgress

extension NSNib.Name {
	static let mainWindowController = NSNib.Name("MainWindowController")
}

class MainWindowController: NSWindowController {

	private var progressObserver: NSKeyValueObservation?

	lazy var circularProgress = with(CircularProgressView(frame: CGRect(widthHeight: 160))) {
		$0.foreground = .appTheme
		$0.strokeWidth = 2
		$0.percentLabelLayer.setAutomaticContentsScale()
		$0.percentLabelLayer.implicitAnimations = false
		$0.layer?.backgroundColor = .clear
		$0.isHidden = true
		$0.centerInWindow(window)
	}

	lazy var videoDropView = with(VideoDropView()) {
		$0.frame = window!.contentView!.frame
		$0.dropText = "Drop a Video to Convert to GIF"
		$0.onComplete = { url in
			self.convert(url.first!)
		}
	}

	var choosenDimensions: CGSize = .zero
	var choosenFrameRate: Int?

	var isRunning: Bool = false {
		didSet {
			if isRunning {
				videoDropView.isHidden = true
			} else {
				videoDropView.fadeIn()
			}

			circularProgress.isHidden = !isRunning
		}
	}

    override func windowDidLoad() {
        super.windowDidLoad()

		with(window!) {
			$0.titleVisibility = .hidden
			$0.appearance = NSAppearance(named: .vibrantDark)
			$0.tabbingMode = .disallowed
			$0.titlebarAppearsTransparent = true
			$0.isMovableByWindowBackground = true
			$0.styleMask.remove([.resizable, .fullScreen])
			$0.styleMask.insert(.fullSizeContentView)
			$0.isRestorable = false
			$0.setFrame(CGRect(width: 360, height: 240), display: true)
			$0.center()
		}

		let view = window!.contentView!
		view.addSubview(circularProgress)
		view.addSubview(videoDropView, positioned: .above, relativeTo: nil)

		window!.makeKeyAndOrderFront(nil) /// TODO: This is dirty, find a better way
    }

	override var windowNibName: NSNib.Name? {
		return .mainWindowController
	}

	func convert(_ inputUrl: URL) {
		// We already specify the UTIs we support, so this can only happen on invalid but supported files
		guard inputUrl.isVideoDecodable else {
			Misc.alert(title: "Video not supported", text: "The video you tried to convert could not be read.")
			return
		}

		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		panel.directoryURL = inputUrl.directoryURL
		panel.nameFieldStringValue = inputUrl.changingFileExtension(to: "gif").filename
		panel.prompt = "Convert"
		panel.message = "Choose where to save the GIF"

		let accessoryViewController = SavePanelAccessoryViewController()
		accessoryViewController.inputUrl = inputUrl

		accessoryViewController.onDimensionChange = { dimension in
			self.choosenDimensions = dimension
		}

		accessoryViewController.onFramerateChange = { frameRate in
			self.choosenFrameRate = frameRate
		}

		panel.accessoryView = accessoryViewController.view

		panel.beginSheetModal(for: window!) {
			if $0 == .OK {
				self.startConversion(inputUrl: inputUrl, outputUrl: panel.url!)
			}
		}
	}

	func startConversion(inputUrl: URL, outputUrl: URL) {
		guard !isRunning else {
			return
		}

		isRunning = true

		circularProgress.animated = false
		circularProgress.progress = 0
		circularProgress.animated = true

		let progress = Progress(totalUnitCount: 1)

		progress.performAsCurrent(withPendingUnitCount: 1) {
			let conversion = Gifski.Conversion(
				input: inputUrl,
				output: outputUrl,
				quality: defaults["outputQuality"] as! Double,
				dimensions: self.choosenDimensions,
				frameRate: self.choosenFrameRate
			)
			Gifski.run(conversion) { error in
				DispatchQueue.main.async {
					if let error = error {
						fatalError(error.localizedDescription)
					}
					self.circularProgress.percentLabelLayer.string = "✔"
					self.circularProgress.fadeOut(delay: 1) {
						self.isRunning = false
					}
				}
			}
		}

		progressObserver = progress.observe(\.fractionCompleted) { progress, _ in
			self.circularProgress.progress = CGFloat(progress.fractionCompleted)
		}

		DockProgress.progress = progress
		DockProgress.style = .circle(radius: 55, color: .appTheme)
	}

	// MARK: -

	@objc
	func open(_ sender: AnyObject) {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = false
		panel.canCreateDirectories = false
		panel.allowedFileTypes = System.supportedVideoTypes

		panel.beginSheetModal(for: window!) {
			if $0 == .OK {
				self.convert(panel.url!)
			}
		}
	}

	@objc
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(open(_:))?:
			return !isRunning
		default:
			return super.validateMenuItem(menuItem)
		}
	}

}
