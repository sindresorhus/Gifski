import SwiftUI
import UniformTypeIdentifiers

struct MainScreen: View {
	@Environment(AppState.self) private var appState
	@State private var isDropTargeted = false
	@State private var isWelcomeScreenPresented = false

	var body: some View {
		@Bindable var appState = appState
		NavigationStack(path: $appState.navigationPath) {
			StartScreen()
				.navigationDestination(for: Route.self) {
					switch $0 {
					case .edit(let url, let asset, let metadata): // TODO: Make a `Job` struct for this?
						EditScreen(url: url, asset: asset, metadata: metadata)
							// Ensures @State properties are reset when loading a new video.
							.id(url)
					case .conversion(let conversion):
						ConversionScreen(conversion: conversion)
					case .completed(let data, let url, let sourceURL):
						CompletedScreen(data: data, url: url, sourceURL: sourceURL)
					}
				}
		}
		.frame(width: 760, height: 640)
		.fileImporter(
			isPresented: $appState.isFileImporterPresented,
			allowedContentTypes: Device.supportedVideoTypes
		) {
			do {
				appState.start(try $0.get())
			} catch {
				appState.error = error
			}
		}
		.fileDialogCustomizationID("import")
		.fileDialogMessage("Choose a MP4 or MOV video to convert to an animated GIF")
		.fileDialogDefaultDirectory(.downloadsDirectory)
//		.backgroundWithMaterial(.underWindowBackground, blendingMode: .behindWindow)
		.alert(error: $appState.error)
		.border(isDropTargeted ? Color.accentColor : .clear, width: 5, cornerRadius: 10)
		// Using `onDrop` with delegate instead of `.dropDestination` as it provides better UX with pre-drop validation feedback.
		.onDrop(
			of: appState.isConverting || appState.isOpeningVideo
				? []
				: [UTType.fileURL.identifier] + NSFilePromiseReceiver.readableDraggedTypes,
			delegate: AnyDropDelegate(
				isTargeted: $isDropTargeted.animation(.easeInOut(duration: 0.2)),
				onValidate: {
					// Do not check movie type here. During hover, synchronous pasteboard type checks can fail for valid movie files, which prevents the drop highlight from appearing.
					$0.hasFileURLs || $0.firstMovieFilePromiseReceiver != nil
				},
				onPerform: {
					/*
					The macOS screen-recording thumbnail (`screencaptureui`) vends its recording as a file promise. Claim it directly: the source writes the file into a directory we own before it deletes its own temporary file. The plain `file://` path below races with that teardown, so the open would silently fail and the recording would be lost.
					*/
					if let promiseReceiver = $0.firstMovieFilePromiseReceiver {
						appState.start(promiseReceiver)
						return true
					}

					// Validate synchronously that the dropped file is a movie before `AppState.start(_:)` resets navigation for the new import.
					guard $0.firstMovieFileURL != nil else {
						return false
					}

					/*
					IMPORTANT: Open the URL from the item provider, not from `firstMovieFileURL`/the drag pasteboard.

					`NSItemProvider.getURL()` goes through the sandbox broker (Powerbox), which vends a security-scoped URL and shows the macOS file-access permission prompt (e.g. for the Downloads/Desktop folder) when needed. Reading the URL directly from the drag pasteboard returns a plain `file://` URL that bypasses the broker, so the app is never granted access, the prompt never appears, and the open silently fails. We use the pasteboard read above only for synchronous movie-type validation, never to actually open the file.

					Do not "simplify" this back to opening `firstMovieFileURL` directly. That regressed window drops in 3.0.x.
					*/
					guard let itemProvider = $0.itemProviders(for: [.fileURL]).first else {
						return false
					}

					appState.start(itemProvider)

					return true
				}
			)
		)
		.alert2(
			"Welcome to Gifski!",
			message:
				"""
				Keep in mind that the GIF image format is very space inefficient. Only convert short video clips unless you want huge files.

				If you have any feedback, bug reports, or feature requests, use the feedback button in the “Help” menu. We quickly respond to all submissions.

				Known issue: Dragging from a Dock folder into the window doesn't work because of a macOS bug.
				""",
			isPresented: $isWelcomeScreenPresented
		) {
			Button("Get Started") {}
		}
		.task {
			if SSApp.isFirstLaunch {
				isWelcomeScreenPresented = true
			}
		}
		.task {
			#if DEBUG
//			appState.isFileImporterPresented = true
			#endif
		}
		.toolbar {
			Color.clear
				.frame(width: 0, height: 0)
		}
		// `.materialActiveAppearance` does not currently work here. Remove `.windowIsVibrant` when it does.
//		.containerBackground(.thinMaterial.materialActiveAppearance(.active), for: .window)
		.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
		.windowResizeBehavior(.disabled)
		.windowTabbingMode(.disallowed)
		.windowCollectionBehavior(.fullScreenNone)
		.windowIsMovableByWindowBackground()
		.windowIsVibrant()
	}
}

#Preview {
	MainScreen()
}
