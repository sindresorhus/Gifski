import Cocoa
import ProgressKit
import DockProgress

extension NSColor {
	static let appTheme = NSColor(named: NSColor.Name("Theme"))!
}

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	let mainWindowController = MainWindowController()

	var hasFinishedLaunching = false
	var urlsToConvertOnLaunch: URL!

	func applicationWillFinishLaunching(_ notification: Notification) {
		defaults.register(defaults: [
			"NSApplicationCrashOnExceptions": true,
			"NSFullScreenMenuItemEverywhere": false,
			"outputQuality": 1
		])
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
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
			Misc.alert(title: "Max one file", text: "You can only convert a single file at the time")
			return
		}

		let videoUrl = urls.first!

		/// TODO: Simplify this. Make a function that calls the input when the app finished launching, or right away if it already has.
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
}
