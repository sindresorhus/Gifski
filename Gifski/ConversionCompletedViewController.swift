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
		setUp(url: gifUrl)

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
			draggableFile.layer?.animateScaleMove(
				fromScale: 3,
				fromY: Double(view.frame.height + draggableFile.frame.size.height)
			)
			wrapperView.fadeIn(duration: 0.5, delay: 0.15, completion: nil)
		}

		delay(seconds: 1) { [weak self] in
			guard let self = self else {
				return
			}

			self.tooltip.show(from: self.draggableFile, preferredEdge: .maxY)
		}

		if Defaults[.successfulConversionsCount] == 5 {
			SKStoreReviewController.requestReview()
		}
	}

	private func setUpUI() {
		wrapperView.isHidden = true
		fileNameLabel.maximumNumberOfLines = 1
		fileNameLabel.textColor = .labelColor
		fileNameLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)

		fileSizeLabel.maximumNumberOfLines = 1
		fileSizeLabel.textColor = .secondaryLabelColor
		fileSizeLabel.font = .systemFont(ofSize: 12)

		draggableFileWrapper.addSubview(draggableFile)
		draggableFileWrapper.wantsLayer = true
		draggableFileWrapper.layer?.masksToBounds = false
		draggableFile.constrainEdgesToSuperview()
	}

	private func setUp(url: URL) {
		draggableFile.fileUrl = url
		fileNameLabel.text = url.filename
		fileSizeLabel.text = url.fileSizeFormatted

		shareButton.sendAction(on: .leftMouseDown)
		shareButton.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			NSSharingService.share(items: [url as NSURL], from: self.shareButton)
		}

		copyButton.onAction = { [weak self] _ in
			let pasteboard = NSPasteboard.general
			pasteboard.clearContents()
			pasteboard.writeObjects([url as NSURL])

			self?.copyButton.title = "Copied!"
			self?.copyButton.isEnabled = false
			delay(seconds: 1) {
				self?.copyButton.title = "Copy"
				self?.copyButton.isEnabled = true
			}
		}

		saveAsButton.onAction = { [weak self] _ in
			guard let self = self else {
				return
			}

			let inputUrl = self.conversion.video

			let panel = NSSavePanel()
			panel.canCreateDirectories = true
			panel.allowedFileTypes = [FileType.gif.identifier]
			panel.directoryURL = inputUrl.directoryURL
			panel.nameFieldStringValue = inputUrl.filenameWithoutExtension
			panel.message = "Choose where to save the GIF"

			panel.beginSheetModal(for: self.view.window!) { response in
				guard
					response == .OK,
					let outputUrl = panel.url
				else {
					return
				}

				// Give the system time to close the sheet.
				DispatchQueue.main.async {
					do {
						try FileManager.default.copyItem(at: url, to: outputUrl, overwrite: true)
					} catch {
						error.presentAsModalSheet(for: self.view.window)
					}
				}
			}
		}
	}

	private func setUpDropView() {
		let videoDropController = VideoDropViewController(dropLabelIsHidden: true)
		add(childController: videoDropController)
	}

	@IBAction private func backButton(_ sender: NSButton) {
		// It's safe to force-unwrap as there's no scenario where it will be nil.
		push(viewController: AppDelegate.shared.previousEditViewController!)
	}
}

extension ConversionCompletedViewController: QLPreviewPanelDataSource {
	@IBAction private func quickLook(_ sender: Any) {
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

extension ConversionCompletedViewController: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(quickLook(_:))?:
			return true
		default:
			return false
		}
	}
}
