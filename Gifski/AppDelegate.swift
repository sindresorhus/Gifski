import Cocoa
import Fabric
import Crashlytics

extension NSColor {
	static let appTheme = NSColor.controlAccentColorPolyfill
}

extension Defaults.Keys {
	static let outputQuality = Defaults.Key<Double>("outputQuality", default: 1)
}

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	lazy var mainWindowController = MainWindowController()
	var hasFinishedLaunching = false
	var urlsToConvertOnLaunch: URL!

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
		NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = true

		if urlsToConvertOnLaunch != nil {
			mainWindowController.convert(urlsToConvertOnLaunch)
		}
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		guard !mainWindowController.isRunning else {
			return
		}

		guard urls.count == 1 else {
			NSAlert.showModal(
				for: mainWindowController.window,
				title: "Max one file",
				message: "You can only convert a single file at the time"
			)
			return
		}

		let videoUrl = urls.first!

		// TODO: Simplify this. Make a function that calls the input when the app finished launching, or right away if it already has.
		if hasFinishedLaunching {
			mainWindowController.convert(videoUrl)
		} else {
			// This method is called before `applicationDidFinishLaunching`,
			// so we buffer it up a video is "Open with" this app
			urlsToConvertOnLaunch = videoUrl
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return true
	}

	func application(_ application: NSApplication, willPresentError error: Error) -> Error {
		#if !DEBUG
			Crashlytics.sharedInstance().recordError(error)
		#endif

		return error
	}
}
