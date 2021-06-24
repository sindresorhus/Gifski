import Cocoa
import Quartz
import UserNotifications
import StoreKit
import Defaults

final class ConversionCompletedViewController: NSViewController {
	@IBOutlet private var draggableFileWrapper: NSView!
	@IBOutlet private var fileNameLabel: Label!
	@IBOutlet private var fileSizeLabel: Label!
	@IBOutlet private var saveAsButton: NSButton!
	@IBOutlet private var shareButton: NSButton!
	@IBOutlet private var copyButton: NSButton!
	@IBOutlet private var wrapperView: NSView!

	private let draggableFile = DraggableFile()
	private var conversion: Gifski.Conversion!
	private var gifUrl: URL!

	private let tooltip = Tooltip(
		identifier: "conversionCompletedTips",
		text: "Go ahead and drag the thumbnail to the Finder or Safari! You can also press Space to enlarge the preview.",
		showOnlyOnce: true,
		maxWidth: 260
	)

	convenience init(conversion: Gifski.Conversion, gifUrl: URL) {
		self.init()

		self.conversion = conversion
		self.gifUrl = gifUrl
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		setUpUI()
		setUpDropView()
		setUp()

		if !NSApp.isActive || view.window?.isVisible == false {
			let notification = UNMutableNotificationContent()
			notification.title = "Conversion Completed"
			notification.subtitle = conversion.video.filename
			let request = UNNotificationRequest(identifier: "conversionCompleted", content: notification, trigger: nil)
			// UNUserNotificationCenter.current().add(request)
			AppDelegate.shared.notificationCenter.add(request)
		}
	}

	override func viewDidAppear() {
		super.viewDidAppear()

		// This is needed for Quick Look to work.
		view.window?.makeFirstResponder(self)

		if wrapperView.isHidden {
			if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
				draggableFile.layer?.animateScaleMove(
					fromScale: 3,
					fromY: Double(view.frame.height + draggableFile.frame.size.height)
				)
			}

			wrapperView.fadeIn(duration: 0.5, delay: 0.15, completion: nil)
		}

		delay(seconds: 1) { [weak self] in
			guard let self = self else {
				return
			}

			self.tooltip.show(from: self.draggableFile, preferredEdge: .maxY)
		}

		SSApp.requestReviewAfterBeingCalledThisManyTimes([5, 100, 1000])
	}

	private func setUpUI() {
		wrapperView.isHidden = true
		fileNameLabel.maximumNumberOfLines = 1
		fileNameLabel.textColor = .labelColor
		fileNameLabel.font = .systemFont(ofSize: 14, weight: .semibold)

		fileSizeLabel.maximumNumberOfLines = 1
		fileSizeLabel.textColor = .secondaryLabelColor
		fileSizeLabel.font = .systemFont(ofSize: 12)

		draggableFileWrapper.addSubview(draggableFile)
		draggableFileWrapper.wantsLayer = true
		draggableFileWrapper.layer?.masksToBounds = false
		draggableFile.constrainEdgesToSuperview()
	}

	private func setUp() {
		draggableFile.fileUrl = gifUrl
		fileNameLabel.text = gifUrl.filename
		fileSizeLabel.text = gifUrl.fileSizeFormatted

		copyButton.onAction = { [weak self] _ in
			self?.copyGif()
		}

		shareButton.sendAction(on: .leftMouseDown)
		shareButton.onAction = { [weak self] _ in
			self?.shareGif()
		}

		saveAsButton.onAction = { [weak self] _ in
			self?.saveGif()
		}
	}

	private func copyGif() {
		NSPasteboard.general.with {
			$0.writeObjects([gifUrl as NSURL])
			$0.setString(gifUrl.filenameWithoutExtension, forType: .urlName)
		}

		copyButton.title = "Copied!"
		copyButton.isEnabled = false

		SSApp.runOnce(identifier: "copyWarning") {
			NSAlert.showModal(
				for: copyButton.window,
				title: "The GIF was copied to the clipboard.",
				message: "However…",
				buttonTitles: [
					"Continue"
				],
				defaultButtonIndex: -1
			)

			NSAlert.showModal(
				for: copyButton.window,
				title: "Please read!",
				message: "Many apps like Chrome and Slack do not properly handle copied animated GIFs and will paste them as non-animated PNG.\n\nInstead, drag and drop the GIF into such apps.",
				defaultButtonIndex: -1
			)
		}

		delay(seconds: 1) { [weak self] in
			guard let self = self else {
				return
			}

			self.copyButton.title = "Copy"
			self.copyButton.isEnabled = true
		}
	}

	private func shareGif() {
		NSSharingService.share(items: [gifUrl as NSURL], from: shareButton)
	}

	private func saveGif() {
		let inputUrl = conversion.video

		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		// TODO: Use `.allowedContentTypes` here when targeting macOS 11.
		panel.allowedFileTypes = [FileType.gif.identifier]
		panel.nameFieldStringValue = inputUrl.filenameWithoutExtension
		panel.message = "Choose where to save the GIF"

		// Prevent the default directory to be a temporary directory or read-only volume, for example, when directly dragging a screen recording into Gifski. Setting it to the downloads directory is required as otherwise it will automatically use the same directory as used in the open panel, which could be a read-only volume.
		panel.directoryURL = inputUrl.directoryURL.canBeDefaultSavePanelDirectory
			? inputUrl.directoryURL
			: URL.downloadsDirectory

		panel.beginSheetModal(for: view.window!) { [weak self] response in
			guard
				let self = self,
				response == .OK,
				let outputUrl = panel.url
			else {
				return
			}

			// Give the system time to close the sheet.
			DispatchQueue.main.async {
				do {
					try FileManager.default.copyItem(at: self.gifUrl, to: outputUrl, overwrite: true)
				} catch {
					error.presentAsModalSheet(for: self.view.window)
					self.saveGif()
				}
			}
		}
	}

	private func setUpDropView() {
		let videoDropController = VideoDropViewController(dropLabelIsHidden: true)
		add(childController: videoDropController)
	}

	@IBAction
	private func backButton(_ sender: NSButton) {
		// It's safe to force-unwrap as there's no scenario where it will be nil.
		let viewController = AppDelegate.shared.previousEditViewController!
		viewController.isConverting = false
		push(viewController: viewController)
	}
}

// MARK: First responders
extension ConversionCompletedViewController {
	@objc
	func copy(_ sender: Any) {
		copyGif()
	}

	@objc
	func saveDocumentAs(_ sender: Any) {
		saveGif()
	}
}

extension ConversionCompletedViewController: QLPreviewPanelDataSource {
	@IBAction
	private func quickLook(_ sender: Any) {
		quickLookPreviewItems(nil)
	}

	override func quickLook(with event: NSEvent) {
		quickLookPreviewItems(nil)
	}

	override func quickLookPreviewItems(_ sender: Any?) {
		guard let panel = QLPreviewPanel.shared() else {
			return
		}

		panel.toggle()
	}

	override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

	override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
		panel.delegate = self
		panel.dataSource = self
	}

	override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
		panel.dataSource = nil
		panel.delegate = nil
	}

	func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

	func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
		gifUrl as NSURL
	}
}

extension ConversionCompletedViewController: QLPreviewPanelDelegate {
	func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> CGRect {
		draggableFile.imageView?.boundsInScreenCoordinates ?? .zero
	}

	func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect: UnsafeMutablePointer<CGRect>!) -> Any! {
		draggableFile.image
	}
}
