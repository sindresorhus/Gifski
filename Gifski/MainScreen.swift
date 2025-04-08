import SwiftUI

struct MainScreen: View {
	@Environment(AppState.self) private var appState
	@State private var isDropTargeted = false
	@State private var isWelcomeScreenPresented = false
	@Default(.outputCrop) private var outputCrop
	@Default(.outputCropRect) private var outputCropRect

	var body: some View {
		@Bindable var appState = appState
		NavigationStack(path: $appState.navigationPath) {
			StartScreen()
				.navigationDestination(for: Route.self) {
					switch $0 {
					case .edit(let url, let asset, let metadata): // TODO: Make a `Job` struct for this?
						EditScreen(url: url, asset: asset, metadata: metadata)
					case .conversion(let conversion):
						ConversionScreen(conversion: conversion)
					case .completed(let data, let url):
						CompletedScreen(data: data, url: url)
					case .editCrop(let asset, let metadata, let bounceGIF):
						EditCropScreen(
							outputCrop: $outputCrop,
							outputCropRect: $outputCropRect,
							asset: asset,
							metadata: metadata,
							bounceGIF: bounceGIF
						)
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
		// TODO: use `.dropDestination` here when targeting macOS 15. It's stil buggy in macOS 14 (from experience with Aiko)
		.onDrop(
			of: appState.isConverting ? [] : [.fileURL],
			delegate: AnyDropDelegate(
				isTargeted: $isDropTargeted.animation(.easeInOut(duration: 0.2)),
				onValidate: {
					$0.hasFileURLsConforming(to: Device.supportedVideoTypes)
				},
				onPerform: {
					guard let itemProvider = $0.itemProviders(for: [.fileURL]).first else {
						return false
					}

					Task {
						guard let url = await itemProvider.getURL() else {
							return
						}

						appState.start(url)
					}

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
		}
		.windowTabbingMode(.disallowed)
		.windowCollectionBehavior(.fullScreenNone)
		.windowIsMovableByWindowBackground()
		.windowIsResizable(false)
		.windowIsRestorable(false)
		.windowTitlebarAppearsTransparent()
		.windowIsVibrant()
	}
}

#Preview {
	MainScreen()
}
