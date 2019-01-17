import Cocoa
import Carbon.HIToolbox

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
			this.dropText = nil
		}
	}

	private lazy var showInFinderButton = with(CustomButton()) {
		$0.title = "Show in Finder"
		$0.frame = CGRect(x: 0, y: 0, width: 110, height: 30)
		$0.textColor = .appTheme
		$0.backgroundColor = .clear
		$0.borderWidth = 1
		$0.isHidden = true
		$0.centerInWindow(window)
	}

	private lazy var cancelButton = with(CustomButton()) {
		$0.title = "Cancel"
		$0.frame = CGRect(x: 0, y: 0, width: 110, height: 30)
		$0.textColor = .appTheme
		$0.backgroundColor = .clear
		$0.borderWidth = 1
		$0.isHidden = true
		$0.centerInWindow(window)
	}

	private var choosenDimensions: CGSize?
	private var choosenFrameRate: Int?

	var isRunning: Bool = false {
		didSet {
			if isRunning {
				videoDropView.isHidden = true
				showInFinderButton.isHidden = true
			} else {
				videoDropView.isHidden = false
				showInFinderButton.fadeIn()
			}

			circularProgress.isHidden = !isRunning
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

		view?.addSubview(circularProgress)
		view?.addSubview(videoDropView, positioned: .above, relativeTo: nil)
		view?.addSubview(showInFinderButton)
		view?.addSubview(cancelButton)

		NSEvent.addLocalMonitorForEvents(matching: .keyUp) {
			guard Int($0.keyCode) == kVK_Escape else {
				return $0
			}
			self.cancelConversion(nil)
			return nil
		}

		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: false)

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

		showInFinderButton.onAction = { _ in
			NSWorkspace.shared.activateFileViewerSelecting([outputUrl])
		}

		cancelButton.onAction = cancelConversion

		isRunning = true

		let progress = Progress(totalUnitCount: 1)
		circularProgress.progressInstance = progress
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
				if let error = error {
					fatalError(error.localizedDescription)
				}

				// Workaround for https://github.com/sindresorhus/gifski-app/issues/46
				progress.completedUnitCount = 0

				DispatchQueue.main.async {
					self.circularProgress.fadeOut(delay: 1) {
						self.circularProgress.resetProgress()
						self.isRunning = false
					}
				}
			}
		}
	}

	private func cancelConversion(_: NSControl?) {
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
