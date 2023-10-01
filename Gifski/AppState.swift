import SwiftUI
import UserNotifications
import DockProgress

@MainActor
@Observable
final class AppState {
	static let shared = AppState()

	var navigationPath = [Route]()
	var isFileImporterPresented = false

	// TODO: This can be inferred by checking the last element of navigationPath.
	var isConverting = false

	var error: Error?

	init() {
		DockProgress.style = .squircle(color: .white.withAlphaComponent(0.7))

		DispatchQueue.main.async { [self] in
			didLaunch()
		}
	}

	private func didLaunch() {
		NSApp.servicesProvider = self

		// We have to include `.badge` otherwise system settings does not show the checkbox to turn off sounds. (macOS 12.4)
		UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .badge]) { _, _ in }
	}

	func start(_ url: URL) {
		_ = url.startAccessingSecurityScopedResource()

		// We have to nil it out first and dispatch, otherwise it shows the old video. (macOS 14.3)
		navigationPath = []

		Task { @MainActor [self] in
			do {
				// TODO: Simplify the validator.
				let (asset, metadata) = try await VideoValidator.validate(url)
				navigationPath = [.edit(url, asset, metadata)]
			} catch {
				self.error = error
			}
		}
	}

	/**
	Returns `nil` if it should not continue.
	*/
	fileprivate func extractSharedVideoUrlIfAny(from url: URL) -> URL? {
		guard url.host == "shareExtension" else {
			return url
		}

		guard
			let path = url.queryDictionary["path"],
			let appGroupShareVideoUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.videoShareGroupIdentifier)?.appendingPathComponent(path, isDirectory: false)
		else {
			NSAlert.showModal(
				for: SSApp.swiftUIMainWindow,
				title: "Could not retrieve the shared video."
			)
			return nil
		}

		return appGroupShareVideoUrl
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		// Set launch completions option if the notification center could not be set up already.
		LaunchCompletions.applicationDidLaunch()
	}

	// TODO: Try to migrate to `.onOpenURL` when targeting macOS 15.
	func application(_ application: NSApplication, open urls: [URL]) {
		guard
			urls.count == 1,
			let videoUrl = urls.first
		else {
			NSAlert.showModal(
				for: SSApp.swiftUIMainWindow,
				title: "Gifski can only convert a single file at the time."
			)

			return
		}

		guard let videoUrl2 = AppState.shared.extractSharedVideoUrlIfAny(from: videoUrl) else {
			return
		}

		// Start video conversion on launch
		LaunchCompletions.add {
			AppState.shared.start(videoUrl2)
		}
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		if AppState.shared.isConverting {
			let response = NSAlert.showModal(
				for: SSApp.swiftUIMainWindow,
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

	func applicationWillTerminate(_ notification: Notification) {
		UNUserNotificationCenter.current().removeAllDeliveredNotifications()
	}
}

extension AppState {
	/**
	This is called from NSApp as a service resolver.
	*/
	@objc
	func convertToGIF(_ pasteboard: NSPasteboard, userData: String, error: NSErrorPointer) {
		guard let url = pasteboard.fileURLs().first else {
			return
		}

		Task { @MainActor in
			start(url)
		}
	}
}
