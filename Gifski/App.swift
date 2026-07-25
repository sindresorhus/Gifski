import SwiftUI

@main
struct AppMain: App {
	private let appState = AppState.shared
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

	init() {
		setUpConfig()
	}

	var body: some Scene {
		Window(SSApp.name, id: "main") {
			MainScreen()
				.environment(appState)
		}
		.windowResizability(.contentSize)
		.windowToolbarStyle(.unifiedCompact)
//		.windowBackgroundDragBehavior(.enabled) // Does not work. (macOS 15.2)
		.defaultPosition(.center)
		.restorationBehavior(.disabled)
		.commands {
			CommandGroup(replacing: .newItem) {
				Button("Open…", systemImage: "arrow.up.forward.square") {
					appState.isFileImporterPresented = true
				}
				.keyboardShortcut("o")
				.disabled(appState.isConverting || appState.isOpeningVideo)
			}
			CommandGroup(replacing: .importExport) {
				Button("Export as Video…", systemImage: "square.and.arrow.up") {
					appState.onExportAsVideo?()
				}
				.keyboardShortcut("e")
				.disabled(!appState.isOnEditScreen)
			}
			CommandGroup(replacing: .textEditing) {
				Toggle(
					"Preview",
					systemImage: "eye",
					isOn: appState.toggleMode(mode: .preview)
				)
				.keyboardShortcut("p", modifiers: [.command, .shift])
				.disabled(!appState.isOnEditScreen)
				.help("Preview is only available when editing a video")
				Toggle(
					"Crop",
					systemImage: "crop",
					isOn: appState.toggleMode(mode: .editCrop)
				)
				.keyboardShortcut("c", modifiers: [.command, .shift])
				.disabled(!appState.isOnEditScreen)
			}
			CommandGroup(replacing: .help) {
				Link(
					"Website",
					systemImage: "safari",
					destination: "https://sindresorhus.com/gifski"
				)
				Link(
					"Source Code",
					systemImage: "chevron.left.forwardslash.chevron.right",
					destination: "https://github.com/sindresorhus/Gifski"
				)
				Link(
					"Gifski Library",
					systemImage: "shippingbox",
					destination: "https://github.com/ImageOptim/gifski"
				)
				Divider()
				RateOnAppStoreButton(appStoreID: "1351639930")
				ShareAppButton(appStoreID: "1351639930")
				Divider()
				Button("Copy Logs", systemImage: "doc.on.clipboard") {
					appState.copyDiagnosticLogs()
				}
				SendFeedbackButton()
			}
		}
		Settings {
			SettingsScreen()
		}
	}

	private func setUpConfig() {
		UserDefaults.standard.register(defaults: [
			"NSApplicationCrashOnExceptions": true
		])

		SSApp.initSentry("https://0ab0665326c54956f3caa10fc2f525d1@o844094.ingest.sentry.io/4505991507738624")

		SSApp.setUpExternalEventListeners()
	}
}
