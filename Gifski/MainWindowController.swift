import Cocoa

final class MainWindowController: NSWindowController {
	private var progressObserver: NSKeyValueObservation?

	/// TODO: Find a way to set the `frame` after init
	private lazy var circularProgress = with(CircularProgress(frame: CGRect(widthHeight: 160))) {
		$0.color = .appTheme
		$0.isHidden = true
		$0.centerInWindow(window)
	}

	private lazy var videoDropView = with(VideoDropView()) {
		$0.dropText = "Drop a Video to Convert to GIF"
		$0.onComplete = { url in
			self.convert(url.first!)
		}
	}

	private var choosenDimensions: CGSize?
	private var choosenFrameRate: Int?

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

	convenience init() {
		let window = NSWindow.centeredWindow(size: CGSize(width: 360, height: 240))
		self.init(window: window)

		with(window) {
			$0.appearance = NSAppearance(named: .vibrantLight)
			$0.titleVisibility = .hidden
			$0.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
			$0.tabbingMode = .disallowed
			$0.titlebarAppearsTransparent = true
			$0.isMovableByWindowBackground = true
			$0.isRestorable = false

			let vibrancyView = $0.contentView?.insertVibrancyView()
			vibrancyView?.state = .active
		}

		view?.addSubview(circularProgress)
		view?.addSubview(videoDropView, positioned: .above, relativeTo: nil)

		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)

		DockProgress.style = .circle(radius: 55, color: .appTheme)
	}

	func convert(_ inputUrl: URL) {
		// We already specify the UTIs we support, so this can only happen on invalid but supported files
		guard inputUrl.isVideoDecodable else {
			NSAlert.showModal(
				for: window,
				title: "Video not supported",
				message: "The video you tried to convert could not be read."
			)
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

		circularProgress.resetProgress()
		isRunning = true

		let progress = Progress(totalUnitCount: 1)
		circularProgress.progress = progress
		DockProgress.progress = progress

		progress.performAsCurrent(withPendingUnitCount: 1) {
			let conversion = Gifski.Conversion(
				input: inputUrl,
				output: outputUrl,
				quality: defaults[.outputQuality],
				dimensions: self.choosenDimensions,
				frameRate: self.choosenFrameRate
			)

			Gifski.run(conversion) { error in
				DispatchQueue.main.async {
					if let error = error {
						fatalError(error.localizedDescription)
					}

					self.circularProgress.fadeOut(delay: 1) {
						self.isRunning = false
					}
				}
			}
		}
	}

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
		case #selector(open)?:
			return !isRunning
		default:
			return super.validateMenuItem(menuItem)
		}
	}
}
