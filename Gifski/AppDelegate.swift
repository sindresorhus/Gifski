import Cocoa
import UserNotifications
import Fabric
import Crashlytics

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	lazy var mainWindowController = MainWindowController()
	var hasFinishedLaunching = false
	var urlToConvertOnLaunch: URL!

	// Possible workaround for crashing bug because of Crashlytics swizzling.
	var notificationCenter: AnyObject? = {
		if #available(macOS 10.14, *) {
			return UNUserNotificationCenter.current()
		} else {
			return nil
		}
	}()

	func applicationWillFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(defaults: [
			"NSApplicationCrashOnExceptions": true,
			"NSFullScreenMenuItemEverywhere": false
		])
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		if #available(macOS 10.14, *) {
			(notificationCenter as? UNUserNotificationCenter)?.requestAuthorization { _, _ in }
		}

		#if !DEBUG
			Fabric.with([Crashlytics.self])
		#endif

		mainWindowController.showWindow(self)

		hasFinishedLaunching = true
		NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = true
		NSApp.servicesProvider = self

		if urlToConvertOnLaunch != nil {
			mainWindowController.convert(urlToConvertOnLaunch)
		}
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		guard urls.count == 1, let videoUrl = urls.first else {
			NSAlert.showModal(
				for: mainWindowController.window,
				message: "Gifski can only convert a single file at the time."
			)
			return
		}

		var sharedVideoUrl = videoUrl

		if videoUrl.host == "shareExtension" {
			if let path = videoUrl.queryParameters["path"] {
				let appIdentifierPrefix = Bundle.main.infoDictionary!["AppIdentifierPrefix"] as! String
				let appGroupShareVideUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "\(appIdentifierPrefix).gifski_video_share_group")?.appendingPathComponent(path.removingPercentEncoding!)
				sharedVideoUrl = appGroupShareVideUrl!
			} else if let error = videoUrl.queryParameters["error"], error == "true" {
				NSAlert.showModal(
					for: mainWindowController.window,
					message: "An error occured in the share dialog."
				)
				return
			}
		}

		// TODO: Simplify this. Make a function that calls the input when the app finished launching, or right away if it already has.
		if hasFinishedLaunching {
			mainWindowController.convert(sharedVideoUrl.absoluteURL)
		} else {
			// This method is called before `applicationDidFinishLaunching`,
			// so we buffer it up a video is "Open with" this app
			urlToConvertOnLaunch = sharedVideoUrl.absoluteURL
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		if mainWindowController.isConverting {
			let response = NSAlert.showModal(
				for: mainWindowController.window,
				message: "Do you want to continue converting?",
				informativeText: "Gifski is currently converting a video. If you quit, the conversion will be cancelled.",
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
