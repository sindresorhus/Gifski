import Cocoa

final class MainWindowController: NSWindowController {
	private lazy var circularProgress = with(CircularProgress(size: 160)) {
		$0.color = .appTheme
		$0.isHidden = true
		$0.centerInWindow(window)
	}

	private lazy var videoDropView = with(VideoDropView()) {
		$0.dropText = "Drop a Video to Convert to GIF"

		let this = $0
		$0.onComplete = { url in
			self.convert(url.first!)
		}
	}

	private lazy var conversionCompletedView = with(ConversionCompletedView()) {
		$0.isHidden = true
	}

	private lazy var cancelButton = with(CustomButton.circularButton(title: "╳", size: 130)) {
		$0.textColor = .appTheme
		$0[colorGenerator: \.backgroundColor] = {
			NSColor.appTheme.with(alpha: 0.1)
		}
		$0.borderWidth = 0
		$0.isHidden = true
		$0.centerInWindow(window)
	}

	private lazy var hoverView = with(HoverView()) {
		$0.frame = CGRect(x: 0, y: 0, width: 130, height: 130)
		$0.centerInWindow(window)
	}

	private var choosenDimensions: CGSize?
	private var choosenFrameRate: Int?

	var isRunning: Bool = false {
		didSet {
			videoDropView.isHidden = isRunning
			hoverView.onHover = isRunning ? onHover : nil
			cancelButton.isHidden = true

			if let progress = progress, !isRunning {
				circularProgress.fadeOut(delay: 1) {
					self.circularProgress.resetProgress()
					DockProgress.resetProgress()

					if progress.isFinished {
						self.conversionCompletedView.show()
						self.videoDropView.isDropLabelHidden = true
					} else if progress.isCancelled {
						self.videoDropView.isHidden = false
						self.videoDropView.fadeInVideoDropLabel()
					}
				}
			} else {
				circularProgress.isHidden = false
				videoDropView.isDropLabelHidden = true
				conversionCompletedView.isHidden = true
			}
		}
	}

	convenience init() {
		let window = NSWindow.centeredWindow(size: CGSize(width: 360, height: 240))
		self.init(window: window)

		with(window) {
			$0.delegate = self
			$0.titleVisibility = .hidden
			$0.styleMask = [
				.titled,
				.closable,
				.miniaturizable,
				.fullSizeContentView
			]
			$0.tabbingMode = .disallowed
			$0.collectionBehavior = .fullScreenNone
			$0.titlebarAppearsTransparent = true
			$0.isMovableByWindowBackground = true
			$0.isRestorable = false
			$0.makeVibrant()
		}

		view?.addSubview(cancelButton)
		view?.addSubview(circularProgress)
		view?.addSubview(hoverView)
		view?.addSubview(videoDropView, positioned: .above, relativeTo: nil)
		view?.addSubview(conversionCompletedView, positioned: .above, relativeTo: nil)

		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: false)

		DockProgress.style = .circle(radius: 55, color: .appTheme)
	}

	/// Gets called when the Esc key is pressed.
	/// Reference: https://stackoverflow.com/a/42440020
	@objc
	func cancel(_ sender: Any?) {
		cancelConversion()
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

	private var progress: Progress?

	func startConversion(inputUrl: URL, outputUrl: URL) {
		guard !isRunning else {
			return
		}

		conversionCompletedView.fileUrl = outputUrl

		cancelButton.onAction = { _ in
			self.cancelConversion()
		}

		isRunning = true

		progress = Progress(totalUnitCount: 1)
		circularProgress.progressInstance = progress
		DockProgress.progress = progress

		progress?.performAsCurrent(withPendingUnitCount: 1) {
			let conversion = Gifski.Conversion(
				input: inputUrl,
				output: outputUrl,
				quality: defaults[.outputQuality],
				dimensions: self.choosenDimensions,
				frameRate: self.choosenFrameRate
			)

			Gifski.run(conversion) { error in
				DispatchQueue.main.async {
					self.isRunning = false
				}

				guard let error = error else {
					return
				}

				switch error {
				case .cancelled:
					break
				default:
					fatalError(error.localizedDescription)
				}
			}
		}
	}

	private func onHover(_ event: HoverView.Event) {
		switch event {
		case .entered:
			circularProgress.isProgressLabelHidden = true
			cancelButton.fadeIn()
		case .exited:
			circularProgress.isProgressLabelHidden = false
			cancelButton.isHidden = true
		}
	}

	private func cancelConversion() {
		progress?.cancel()
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
}

extension MainWindowController: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(open)?:
			return !isRunning
		default:
			return validateMenuItem(menuItem)
		}
	}
}
