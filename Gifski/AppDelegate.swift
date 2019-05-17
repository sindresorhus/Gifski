import Cocoa
import Fabric
import Crashlytics

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

		// TEMP for testing
		NSAlert.showModalAndReportToCrashlytics(
			message: "The video file is not supported.",
			informativeText: "Please open an issue on https://github.com/sindresorhus/gifski-app or email sindresorhus@gmail.com. ZIP the video and attach it.\n\nInclude this info:",
			debugInfo: "TEST"
		)
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		guard !mainWindowController.isRunning else {
			return
		}

		guard urls.count == 1 else {
			NSAlert.showModal(
				for: mainWindowController.window,
				message: "Gifski can only convert a single file at the time."
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
		Crashlytics.recordNonFatalError(error: error)
		return error
	}
}
