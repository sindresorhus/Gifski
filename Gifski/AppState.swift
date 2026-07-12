import SwiftUI
import UserNotifications
import DockProgress
import OSLog

@MainActor
private final class ImportLog {
	static let shared = ImportLog()

	private let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "com.sindresorhus.Gifski",
		category: "Import"
	)

	private var entries = [String]()

	var text: String {
		entries.joined(separator: "\n")
	}

	func info(_ publicMessage: String, _ privateMessage: @autoclosure () -> String) {
		logger.info("\(publicMessage, privacy: .public)")
		append("info", privateMessage())
	}

	func debug(_ publicMessage: String, _ privateMessage: @autoclosure () -> String) {
		logger.debug("\(publicMessage, privacy: .public)")
		append("debug", privateMessage())
	}

	func error(_ publicMessage: String, _ privateMessage: @autoclosure () -> String) {
		logger.error("\(publicMessage, privacy: .public)")
		append("error", privateMessage())
	}

	private func append(_ level: String, _ text: String) {
		entries.append("[\(Date.now.formatted(date: .numeric, time: .complete))] \(level): \(text)")

		if entries.count > 200 {
			entries.removeFirst(entries.count - 200)
		}
	}
}

@MainActor
@Observable
final class AppState {
	static let shared = AppState()

	var isOnEditScreen: Bool {
		guard case .edit = navigationPath.last else {
			return false
		}

		return true
	}

	var isConverting: Bool {
		guard case .conversion = navigationPath.last else {
			return false
		}

		return true
	}

	var navigationPath = [Route]()
	var isFileImporterPresented = false
	var isOpeningVideo = false

	enum Mode {
		case normal
		case editCrop
		case preview
	}

	var mode = Mode.normal

	var shouldShowPreview: Bool {
		mode == .preview
	}

	var isCropActive: Bool {
		mode == .editCrop
	}

	var onExportAsVideo: (() -> Void)?

	func copyDiagnosticLogs() {
		let importLogs = ImportLog.shared.text

		NSPasteboard.general.with {
			$0.setString(
				"""
				\(SSApp.debugInfo)

				Import Logs
				\(importLogs.isEmpty ? "No logs recorded." : importLogs)
				""",
				forType: .string
			)
		}
	}

	/**
	Provides a binding for a toggle button to access a certain mode.

	The getter returns true if in that mode. Setter will toggle the mode on, but return to initial mode if set to off (if we are in the specified mode).
	*/
	func toggleMode(mode: Mode) -> Binding<Bool> {
		.init(
			get: {
				self.mode == mode
			},
			set: { newValue in
				if newValue {
					self.mode = mode
					return
				}

				guard self.mode == mode else {
					return
				}

				self.mode = .normal
			}
		)
	}

	var error: Error?

	init() {
		DockProgress.style = .squircle(color: .white.opacity(0.7))

		DispatchQueue.main.async { [self] in
			didLaunch()
		}
	}

	private func didLaunch() {
		NSApp.servicesProvider = self

		// We have to include `.badge` otherwise system settings does not show the checkbox to turn off sounds. (macOS 12.4)
		UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .badge]) { _, _ in }

		delay(.seconds(1)) {
			SSApp.runOnce(identifier: "firstLaunch-3-0-0") {
				guard !SSApp.isFirstLaunch else {
					return
				}

				NSAlert.showModal(
					for: NSApp.mainWindow,
					title: "Welcome to Gifski 3",
					message: "Gifski now supports cropping and preview.\n\nNote: Quick Look is no longer available after conversion. It was unreliable, and the preview window is now large enough on its own.\n\nKnown issue: Dragging from a Dock folder into the window may fail due to a macOS bug."
				)
			}
		}
	}

	func start(_ url: URL) {
		guard !isOpeningVideo else {
			ImportLog.shared.info(
				"Ignored open request while another video is opening",
				"Ignored open request while another video is opening: filename=\(url.lastPathComponent), pathExtension=\(url.pathExtension)"
			)
			return
		}

		startOpeningVideo(url)
	}

	private func startOpeningVideo(_ url: URL) {
		// We intentionally do not call `stop` on this one later for simplicity since we will never get a lot of files.
		let didStartSecurityScopedAccess = url.startAccessingSecurityScopedResource()
		let contentType = url.contentType?.identifier ?? "unknown"
		ImportLog.shared.info(
			"Start opening video: pathExtension=\(url.pathExtension), contentType=\(contentType)",
			"Start opening video: filename=\(url.lastPathComponent), pathExtension=\(url.pathExtension), contentType=\(contentType), fileSize=\(url.fileSize)"
		)
		ImportLog.shared.debug(
			"Security scoped access: didStart=\(didStartSecurityScopedAccess)",
			"Security scoped access: filename=\(url.lastPathComponent), didStart=\(didStartSecurityScopedAccess)"
		)

		// We have to nil it out first and dispatch, otherwise it shows the old video. (macOS 14.3)
		navigationPath = []
		isOpeningVideo = true

		// Reset mode to prevent the new EditScreen from inheriting preview/crop state.
		mode = .normal

		Task { [self] in
			defer {
				isOpeningVideo = false
			}

			do {
				ImportLog.shared.info(
					"Validating video",
					"Validating video: filename=\(url.lastPathComponent)"
				)
				// TODO: Simplify the validator.
				let (asset, metadata) = try await VideoValidator.validate(url)
				ImportLog.shared.info(
					"Video validated",
					"Video validated: filename=\(url.lastPathComponent), dimensions=\(metadata.dimensions.formatted), duration=\(metadata.duration.toTimeInterval.formatted(.number.precision(.fractionLength(2)))), hasAudio=\(metadata.hasAudio)"
				)
				navigationPath = [.edit(url, asset, metadata)]
			} catch {
				let nsError = error as NSError
				let recoverySuggestion = nsError.localizedRecoverySuggestion.map { ", recoverySuggestion=\($0)" } ?? ""
				ImportLog.shared.error(
					"Video validation failed: errorDomain=\(nsError.domain), errorCode=\(nsError.code)",
					"Video validation failed: filename=\(url.lastPathComponent), errorDomain=\(nsError.domain), errorCode=\(nsError.code), message=\(error.localizedDescription)\(recoverySuggestion)"
				)
				self.error = error
			}
		}
	}

	func start(_ itemProvider: NSItemProvider) {
		guard !isOpeningVideo else {
			ImportLog.shared.info(
				"Ignored open request while another video is opening",
				"Ignored open request while another video is opening"
			)
			return
		}

		isOpeningVideo = true

		Task { [self] in
			guard let url = await itemProvider.getURL() else {
				isOpeningVideo = false
				return
			}

			startOpeningVideo(url)
		}
	}

	private func handlePromisedVideoError(_ error: Error) {
		isOpeningVideo = false
		let nsError = error as NSError
		ImportLog.shared.error(
			"Failed to receive promised video: errorDomain=\(nsError.domain), errorCode=\(nsError.code)",
			"Failed to receive promised video: errorDomain=\(nsError.domain), errorCode=\(nsError.code), message=\(error.localizedDescription)"
		)
		self.error = error
	}

	/**
	Open a video from a dragged file promise, such as the macOS screen-recording thumbnail (`screencaptureui`).

	The promise source writes the file into a directory we own before it tears down its own temporary file, so the video remains available. This avoids the race in the plain drag-pasteboard path where the source deletes its temporary file before the async open resolves, losing the recording.
	*/
	func start(_ promiseReceiver: NSFilePromiseReceiver) {
		guard !isOpeningVideo else {
			ImportLog.shared.info(
				"Ignored promised video while another video is opening",
				"Ignored promised video while another video is opening"
			)
			return
		}

		let fileTypes = promiseReceiver.fileTypes.joined(separator: ", ")
		ImportLog.shared.info(
			"Receiving promised video: fileTypes=\(fileTypes)",
			"Receiving promised video: fileTypes=\(fileTypes)"
		)

		isOpeningVideo = true

		do {
			let promisedFile = try promiseReceiver.receivePromisedFile()

			Task { [self] in
				do {
					for try await url in promisedFile {
						startOpeningVideo(url)
						return
					}

					isOpeningVideo = false
				} catch {
					handlePromisedVideoError(error)
				}
			}
		} catch {
			handlePromisedVideoError(error)
		}
	}

	/**
	Returns `nil` if it should not continue.
	*/
	fileprivate func extractSharedVideoUrlIfAny(from url: URL) -> URL? {
		guard url.host == "shareExtension" else {
			ImportLog.shared.debug(
				"Using direct open URL: pathExtension=\(url.pathExtension)",
				"Using direct open URL: filename=\(url.lastPathComponent), pathExtension=\(url.pathExtension)"
			)
			return url
		}

		ImportLog.shared.info("Resolving share extension URL", "Resolving share extension URL")

		guard
			let path = url.queryDictionary["path"],
			let appGroupShareVideoUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.appGroupIdentifier)?.appendingPathComponent(path, isDirectory: false)
		else {
			ImportLog.shared.error("Failed to resolve share extension URL", "Failed to resolve share extension URL")
			NSAlert.showModal(
				for: SSApp.swiftUIMainWindow,
				title: "Could not retrieve the shared video."
			)
			return nil
		}

		ImportLog.shared.info(
			"Resolved share extension URL: pathExtension=\(appGroupShareVideoUrl.pathExtension)",
			"Resolved share extension URL: filename=\(appGroupShareVideoUrl.lastPathComponent), pathExtension=\(appGroupShareVideoUrl.pathExtension)"
		)
		return appGroupShareVideoUrl
	}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		ImportLog.shared.info("Application did finish launching", "Application did finish launching")
		// Set launch completions option if the notification center could not be set up already.
		LaunchCompletions.applicationDidLaunch()
	}

	// Using AppDelegate instead of `.onOpenURL` because we need to handle multiple URLs at once to reject multi-file drops with a user-friendly error.
	func application(_ application: NSApplication, open urls: [URL]) {
		ImportLog.shared.info(
			"Received open URLs event: count=\(urls.count), pathExtensions=\(urls.map(\.pathExtension).joined(separator: ", "))",
			"Received open URLs event: count=\(urls.count), pathExtensions=\(urls.map(\.pathExtension).joined(separator: ", "))"
		)

		guard !AppState.shared.isOpeningVideo else {
			ImportLog.shared.info(
				"Ignored open URLs event while another video is opening: count=\(urls.count)",
				"Ignored open URLs event while another video is opening: count=\(urls.count)"
			)
			return
		}

		guard
			urls.count == 1,
			let videoUrl = urls.first
		else {
			ImportLog.shared.error(
				"Rejected open URLs event because it contained \(urls.count) files",
				"Rejected open URLs event because it contained \(urls.count) files"
			)
			NSAlert.showModal(
				for: SSApp.swiftUIMainWindow,
				title: "Gifski can only convert a single file at a time."
			)

			return
		}

		guard let videoUrl2 = AppState.shared.extractSharedVideoUrlIfAny(from: videoUrl) else {
			ImportLog.shared.error("Rejected open URLs event because no usable video URL could be resolved", "Rejected open URLs event because no usable video URL could be resolved")
			return
		}

		// Start video conversion on launch
		LaunchCompletions.add {
			ImportLog.shared.info(
				"Running queued open video completion: pathExtension=\(videoUrl2.pathExtension)",
				"Running queued open video completion: filename=\(videoUrl2.lastPathComponent), pathExtension=\(videoUrl2.pathExtension)"
			)
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

		start(url)
	}
}
