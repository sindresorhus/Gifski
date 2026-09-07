import SwiftUI
import UserNotifications
import StoreKit

struct CompletedScreen: View {
	@Environment(AppState.self) private var appState
	@Environment(\.requestReview) private var requestReview
	@AppStorage("conversionCount") private var conversionCount = 0
	@State private var isFileExporterPresented = false
	@State private var isShowingContent = false
	@State private var isCopyWarning1Presented = false
	@State private var isCopyWarning2Presented = false
	@State private var isDragTipPresented = false

	let data: Data
	let url: URL
	let sourceURL: URL

	var body: some View {
		VStack {
			ImageView(image: NSImage(data: data) ?? NSImage())
				.clipShape(.rect(cornerRadius: 8))
				.shadow(radius: 8)
				// TODO: This is probably fixed in macOS 15. Test.
				// TODO: `.draggable()` does not correctly add a file to the drag pasteboard. (macOS 14.0)
//				.draggable(ExportableGIF(url: url))
				.onDrag { .init(object: url as NSURL) }
				.popover(isPresented: $isDragTipPresented) {
					Text("Go ahead and drag the thumbnail to an app like Finder or Safari")
						.padding()
						.padding(.vertical, 4)
						.onTapGesture {
							isDragTipPresented = false
						}
						.accessibilityAddTraits(.isButton)
				}
				.opacity(isShowingContent ? 1 : -0.5)
				.scaleEffect(isShowingContent ? 1 : 4)
		}
		.fillFrame()
		.safeAreaInset(edge: .bottom) {
			controls
		}
		.scenePadding()
		.fileExporter(
			isPresented: $isFileExporterPresented,
			item: ExportableGIF(url: url),
			defaultFilename: url.filename
		) {
			do {
				let url = try $0.get()
				try? url.setAppAsItemCreator()
			} catch {
				appState.error = error
			}
		}
		.fileDialogDefaultDirectory(saveDialogDirectory)
		.fileDialogMessage("Choose where to save the GIF")
		.fileDialogConfirmationLabel("Save")
		.alert2(
			"The GIF was copied to the clipboard.",
			message: "However…",
			isPresented: $isCopyWarning1Presented
		) {
			Button("Continue") {
				isCopyWarning2Presented = true
			}
		}
		.alert2(
			"Please read!",
			message: "Many apps like Chrome and Slack do not properly handle copied animated GIFs and will paste them as non-animated PNG.\n\nInstead, drag and drop the GIF into such apps.",
			isPresented: $isCopyWarning2Presented
		)
		.toolbar {
			ToolbarSpacer(.fixed)
			ToolbarItem(placement: .primaryAction) {
				Button("New Conversion", systemImage: "plus") {
					appState.isFileImporterPresented = true
				}
				.if(SSApp.isFirstLaunch) {
					$0.labelStyle(.titleAndIcon)
				}
			}
		}
		.navigationTitle(url.filename)
		.navigationSubtitle(url.fileSizeFormatted)
//		.navigationDocument(url) // Doesn't show title (macOS 26.2)
		.task {
			withAnimationWhenNotReduced {
				isShowingContent = true
			}
		}
		.task {
			NSApp.requestUserAttention(.informationalRequest)
			showNotificationIfNeeded()
			showDragTipIfNeeded()
			requestReviewIfNeeded()
		}
	}

	private var controls: some View {
		HStack(spacing: 16) {
			Button("Save", systemImage: "square.and.arrow.down") {
				isFileExporterPresented = true
			}
			.keyboardShortcut("s")
			.help("Save")
			CopyButton {
				copyToClipboard(url)
			}
			.keyboardShortcut("c")
			.help("Copy")
			ShareLink("Share", item: url)
				// TODO: Document this shortcut.
				.keyboardShortcut("s", modifiers: [.command, .shift])
				.help("Share")
		}
		.labelStyle(.iconOnly)
		.controlSize(.extraLarge)
		.buttonStyle(.equalWidth(.constant(0), minimumWidth: 80))
		.buttonStyle(.glass)
		.frame(width: 300)
		.padding()
		.opacity(isShowingContent ? 1 : 0)
	}

	private static let appGroupContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.appGroupIdentifier)

	/**
	The directory the save dialog should open in.

	Defaults to the source video's folder, but falls back to Downloads when that is not a sensible place to save: the hidden app group container (where the Share Extension copies imported videos) or a read-only volume (for example, a file dragged in from a mounted disk image).
	*/
	private var saveDialogDirectory: URL {
		let directory = sourceURL.deletingLastPathComponent()

		guard
			!directory.isVolumeReadonly,
			directory.standardizedFileURL != Self.appGroupContainer?.standardizedFileURL
		else {
			return .downloadsDirectory
		}

		return directory
	}

	private func copyToClipboard(_ url: URL) {
		NSPasteboard.general.with {
			// swiftlint:disable:next legacy_objc_type
			$0.writeObjects([url as NSURL])
			$0.setString(url.filenameWithoutExtension, forType: .urlName)
		}

		SSApp.runOnce(identifier: "copyWarning") {
			isCopyWarning1Presented = true
		}
	}

	private func showNotificationIfNeeded() {
		guard !NSApp.isActive || SSApp.swiftUIMainWindow?.isVisible == false else {
			return
		}

		let notification = UNMutableNotificationContent()
		notification.title = "Conversion Completed"
		notification.subtitle = url.filename
		notification.sound = .default
		let request = UNNotificationRequest(identifier: "conversionCompleted", content: notification, trigger: nil)
		UNUserNotificationCenter.current().add(request)
	}

	private func requestReviewIfNeeded() {
		conversionCount += 1

		guard conversionCount == 5 else {
			return
		}

		#if !DEBUG
		requestReview()
		#endif
	}

	private func showDragTipIfNeeded() {
		SSApp.runOnce(identifier: "CompletedScreen_dragTip") {
			Task {
				try? await Task.sleep(for: .seconds(1))
				isDragTipPresented = true
				try? await Task.sleep(for: .seconds(10))
				isDragTipPresented = false
			}
		}
	}
}
