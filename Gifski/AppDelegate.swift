import Cocoa
import Fabric
import Crashlytics

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	lazy var mainWindowController = MainWindowController()
	var hasFinishedLaunching = false
	var urlToConvertOnLaunch: URL!

	func applicationWillFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(defaults: [
			"NSApplicationCrashOnExceptions": true,
			"NSFullScreenMenuItemEverywhere": false
		])
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
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
		print(urls[0].absoluteURL)
		guard urls.count == 1, let videoUrl = urls.first else {
			NSAlert.showModal(
				for: mainWindowController.window,
				message: "Gifski can only convert a single file at the time."
			)
			return
		}

		// TODO: Simplify this. Make a function that calls the input when the app finished launching, or right away if it already has.
		if hasFinishedLaunching {
			mainWindowController.convert(videoUrl.absoluteURL)
		} else {
			// This method is called before `applicationDidFinishLaunching`,
			// so we buffer it up a video is "Open with" this app
			urlToConvertOnLaunch = videoUrl.absoluteURL
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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
