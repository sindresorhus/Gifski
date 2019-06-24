import Cocoa
import AVFoundation
import Crashlytics

import UserNotifications
import StoreKit

final class ConversionCompletedViewController: NSViewController {
	private lazy var conversionCompletedView = with(ConversionCompletedView()) {
		$0.frame.size = CGSize(width: 360, height: 240)
	}

	private var conversion: Gifski.Conversion!
	private var gifUrl: URL!

	convenience init(conversion: Gifski.Conversion, gifUrl: URL) {
		self.init()

		self.conversion = conversion
		self.gifUrl = gifUrl
	}

	override func loadView() {
		conversionCompletedView.fileUrl = gifUrl
		view = conversionCompletedView
	}

	override func viewDidLoad() {
		super.viewDidLoad()
	}

	override func viewDidAppear() {
		super.viewDidAppear()

		if #available(macOS 10.14, *), defaults[.successfulConversionsCount] == 5 {
			SKStoreReviewController.requestReview()
		}

		if #available(macOS 10.14, *), !NSApp.isActive || self.view.window?.isVisible == false {
			let notification = UNMutableNotificationContent()
			notification.title = "Conversion Completed"
			notification.subtitle = conversion.video.filename
			let request = UNNotificationRequest(identifier: "conversionCompleted", content: notification, trigger: nil)
			UNUserNotificationCenter.current().add(request)
		}
	}
}

final class MainWindowController: NSWindowController {
	convenience init() {
		let window = NSWindow.centeredWindow(size: .zero)
		window.contentViewController = DropVideoViewController()
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

		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: false)

		DockProgress.style = .circle(radius: 55, color: .themeColor)
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

	func convert(_ inputUrl: URL) {
		if let dropVideo = window?.contentViewController as? DropVideoViewController {
			dropVideo.convert(inputUrl)
		} else if !(window?.contentViewController is ConversionViewController) {
			let dropVideo = DropVideoViewController()
			window?.contentViewController?.push(viewController: dropVideo) {
				dropVideo.convert(inputUrl)
			}
		}
	}
}

extension MainWindowController: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(open)?:
			return !(window?.contentViewController is ConversionViewController)
		default:
			return true
		}
	}
}
