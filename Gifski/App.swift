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
			.defaultPosition(.center)
			.handlesExternalEvents(matching: []) // Makes sure it does not open a new window when dragging files onto the Dock icon.
			.commands {
				CommandGroup(replacing: .newItem) {
					Button("Open…") {
						appState.isFileImporterPresented = true
					}
						.keyboardShortcut("o")
						.disabled(appState.isConverting)
				}
				CommandGroup(replacing: .textEditing) {
					Button("Crop") {
						appState.outputCrop.toggle()
					}
					.keyboardShortcut("c", modifiers: [.command, .shift])
					.disabled(!appState.onEditScreen)
				}
				CommandGroup(replacing: .help) {
					Link("Website", destination: "https://sindresorhus.com/Gifski")
					Link("Source Code", destination: "https://github.com/sindresorhus/Gifski")
					Link("Gifski Library", destination: "https://github.com/ImageOptim/gifski")
					Divider()
					RateOnAppStoreButton(appStoreID: "1351639930")
					// TODO: Doesn't work. (macOS 14.3)
//					ShareAppButton(appStoreID: "1351639930")
					Divider()
					SendFeedbackButton()
				}
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
