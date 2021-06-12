import Cocoa
import UserNotifications
import FirebaseCore
import FirebaseCrashlytics
import DockProgress

/**
TODO when targeting macOS 12:
- Rewrite everything to use async/await, AsyncSequence, and actors.
- Rewrite `CheckerboardView` to use `SwiftUI.Canvas`.
*/

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
	private(set) lazy var mainWindowController = MainWindowController()

	var previousEditViewController: EditVideoViewController?

	// Possible workaround for crashing bug because of Crashlytics swizzling.
	let notificationCenter = UNUserNotificationCenter.current()

	func applicationWillFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(
			defaults: [
				"NSApplicationCrashOnExceptions": true,
				"NSFullScreenMenuItemEverywhere": false
			]
		)
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		FirebaseApp.configure()
		NSApp.servicesProvider = self
		notificationCenter.requestAuthorization { _, _ in }

		mainWindowController.showWindow(self)

		// Set launch completions option if the notification center could not be set up already.
		LaunchCompletions.applicationDidLaunch()
	}

	/// Returns `nil` if it should not continue.
	func extractSharedVideoUrlIfAny(from url: URL) -> URL? {
		guard url.host == "shareExtension" else {
			return url
		}

		guard
			let path = url.queryDictionary["path"],
			let appGroupShareVideoUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.videoShareGroupIdentifier)?.appendingPathComponent(path, isDirectory: false)
		else {
			NSAlert.showModal(
				for: mainWindowController.window,
				title: "Could not retrieve the shared video."
			)
			return nil
		}

		return appGroupShareVideoUrl
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		guard
			urls.count == 1,
			let videoUrl = urls.first
		else {
			NSAlert.showModal(
				for: mainWindowController.window,
				title: "Gifski can only convert a single file at the time."
			)
			return
		}

		guard let videoUrl2 = extractSharedVideoUrlIfAny(from: videoUrl) else {
			return
		}

		// Start video conversion on launch
		LaunchCompletions.add { [weak self] in
			self?.mainWindowController.convert(videoUrl2)
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		if mainWindowController.isConverting {
			let response = NSAlert.showModal(
				for: mainWindowController.window,
				title: "Do you want to continue converting?",
				message: "Gifski is currently converting a video. If you quit, the conversion will be cancelled.",
				buttonTitles: [
					"Continue",
					"Quit"
				]
			)

			if response == .alertFirstButtonReturn {
				return .terminateCancel
			}
		}

		return .terminateNow
	}

	func application(_ application: NSApplication, willPresentError error: Error) -> Error {
		Crashlytics.recordNonFatalError(error: error)
		return error
	}
}

extension AppDelegate {
	/// This is called from NSApp as a service resolver
	@objc
	func convertToGif(_ pasteboard: NSPasteboard, userData: String, error: NSErrorPointer) {
		guard let url = pasteboard.fileURLs().first else {
			return
		}

		mainWindowController.convert(url)
	}
}
