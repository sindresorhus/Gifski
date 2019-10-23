import Cocoa
import AVFoundation
import Crashlytics

final class MainWindowController: NSWindowController {
	private let videoValidator = VideoValidator()

	var isConverting: Bool {
		window?.contentViewController is ConversionViewController
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

		DockProgress.style = .circle(radius: 55, color: .themeColor)

		let clickGestureRecognizer = NSClickGestureRecognizer(target: self, action: #selector(open(_:)))
		window.contentViewController?.view.addGestureRecognizer(clickGestureRecognizer)
	}

	@objc
	func open(_ sender: AnyObject) {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = false
		panel.canCreateDirectories = false
		panel.allowedFileTypes = System.supportedVideoTypes

		panel.beginSheetModal(for: window!) { [weak self] in
			if $0 == .OK {
				self?.convert(panel.url!)
			}
		}
	}

	func convert(_ inputUrl: URL) {
		guard
			!isConverting,
			case let .success(asset, videoMetadata) = videoValidator.validate(inputUrl, in: window)
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
