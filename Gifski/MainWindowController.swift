import Cocoa

final class MainWindowController: NSWindowController {
	private let videoValidator = VideoValidator()

	var isConverting: Bool {
		window?.contentViewController is ConversionViewController
	}

	private func showWelcomeScreenIfNeeded() {
		if Device.isRunningNativelyOnMacWithAppleSilicon {
			SSApp.runOnce(identifier: "appleSiliconWelcomeMessage") {
				NSAlert.showModal(
					for: window,
					title: "Gifski on Apple Silicon",
					message:
						"""
						Gifski now runs natively on Apple silicon.

						If you encounter any problems, use the feedback button in the “Help” menu to report it.

						You can temporarily work around the issue by switching back to Rosetta mode: Right-click the app in Finder, select “Get Info”, and then enable “Open using Rosetta”.
						""",
					defaultButtonIndex: -1
				)
			}
		}

		guard SSApp.isFirstLaunch else {
			return
		}

		NSAlert.showModal(
			for: window,
			title: "Welcome to Gifski!",
			message:
				"""
				Keep in mind that the GIF image format is very space inefficient. Only convert short video clips unless you want huge files.
				""",
			buttonTitles: [
				"Continue"
			]
		)

		NSAlert.showModal(
			for: window,
			title: "Feedback Welcome 🙌🏻",
			message:
				"""
				If you have any feedback, bug reports, or feature requests, there's a feedback button in the “Help” menu. We respond to all submissions.
				""",
			buttonTitles: [
				"Get Started"
			],
			defaultButtonIndex: -1
		)
	}

	convenience init() {
		let window = NSWindow.centeredWindow(size: .zero)
		window.contentViewController = VideoDropViewController()
		window.centerNatural()
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

		NSApp.activate(ignoringOtherApps: false)
		window.makeKeyAndOrderFront(nil)

		showWelcomeScreenIfNeeded()
	}

	func presentOpenPanel() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = false
		panel.canCreateDirectories = false
		// TODO: Use `.allowedContentTypes` here when targeting macOS 11.
		panel.allowedFileTypes = Device.supportedVideoTypes

		panel.beginSheetModal(for: window!) { [weak self] in
			guard
				let self = self,
				$0 == .OK,
				let url = panel.url
			else {
				return
			}

			// Give the system time to close the sheet.
			DispatchQueue.main.async {
				self.convert(url)
			}
		}
	}

	@objc
	func open(_ sender: AnyObject) {
		presentOpenPanel()
	}

	func convert(_ inputUrl: URL) {
		guard
			!isConverting,
			case .success(let asset, let videoMetadata) = videoValidator.validate(inputUrl, in: window)
		else {
			return
		}

		let editController = EditVideoViewController(inputUrl: inputUrl, asset: asset, videoMetadata: videoMetadata)
		window?.contentViewController?.push(viewController: editController)
	}
}

extension MainWindowController: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(open)?:
			return !isConverting
		default:
			return true
		}
	}
}
