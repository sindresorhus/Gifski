import SwiftUI
import UserNotifications
import StoreKit

@MainActor
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

	var body: some View {
		VStack {
			ImageView(image: NSImage(data: data) ?? NSImage())
				.clipShape(.rect(cornerRadius: 8))
				.shadow(radius: 8)
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
		.fileDialogCustomizationID("export")
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
			ToolbarItem(placement: .principal) {
				HStack(spacing: 8) {
					Text("\(url.filename)")
//					Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.gif")
						.frame(maxWidth: 200)
						.truncationMode(.middle)
					Text("·")
					Text(url.fileSizeFormatted)
				}
				.font(.system(weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
			}
			ToolbarItem {
				Spacer()
			}
			ToolbarItem(placement: .primaryAction) {
				Button("New Conversion", systemImage: "plus") {
					appState.isFileImporterPresented = true
				}
				.if(SSApp.isFirstLaunch) {
					$0.labelStyle(.titleAndIcon)
				}
			}
		}
//		.navigationTitle(url.filename) // TODO
//		.navigationSubtitle(url.fileSizeFormatted)
		.navigationTitle("")
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
		HStack(spacing: 32) {
			// TODO: We cannot use controlgroup as the sharelink doesn't work then. (macOS 14.0)
//			ControlGroup {
			Button("Save") {
				isFileExporterPresented = true
			}
				.keyboardShortcut("s")
			CopyButton {
				copy(url)
			}
				.keyboardShortcut("c")
			ShareLink("Share", item: url)
				// TODO: Document this shortcut.
				.keyboardShortcut("s", modifiers: [.command, .shift])
		}
		.labelStyle(.titleOnly)
		.controlSize(.extraLarge)
		.buttonStyle(.equalWidth(.constant(0), minimumWidth: 80))
//		.background(.regularMaterial) // Enable if using controlgroup again.
		.frame(width: 300)
		.padding()
		.opacity(isShowingContent ? 1 : 0)
	}

	private func copy(_ url: URL) {
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
