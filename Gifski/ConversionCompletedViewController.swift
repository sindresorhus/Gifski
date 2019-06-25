import Cocoa
import Quartz
import UserNotifications
import StoreKit

final class ConversionCompletedViewController: NSViewController {
    @IBOutlet private var draggableFileWrapper: NSView!
    @IBOutlet private var fileNameLabel: Label!
    @IBOutlet private var fileSizeLabel: Label!
    @IBOutlet private var saveAsButton: NSButton!
    @IBOutlet private var shareButton: NSButton!
    @IBOutlet private var copyButton: NSButton!

    private let draggableFile = DraggableFile()
	private var conversion: Gifski.Conversion!
	private var gifUrl: URL!

	convenience init(conversion: Gifski.Conversion, gifUrl: URL) {
		self.init()

		self.conversion = conversion
		self.gifUrl = gifUrl
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		setupUI()
		setupDropView()
		setup(url: gifUrl)
	}

	override func viewDidAppear() {
		super.viewDidAppear()

		if #available(macOS 10.14, *), defaults[.successfulConversionsCount] == 5 {
			SKStoreReviewController.requestReview()
		}

		if #available(macOS 10.14, *), !NSApp.isActive || self.view.window?.isVisible == false {
			let notification = UNMutableNotificationContent()
			notification.title = "Conversion Completed"
			notification.subtitle = conversion.video.filename
			let request = UNNotificationRequest(identifier: "conversionCompleted", content: notification, trigger: nil)
			UNUserNotificationCenter.current().add(request)
		}
	}

	private func setupUI() {
		fileNameLabel.maximumNumberOfLines = 1
		fileNameLabel.textColor = .labelColor
		fileNameLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)

		fileSizeLabel.maximumNumberOfLines = 1
		fileSizeLabel.textColor = .secondaryLabelColor
		fileSizeLabel.font = .systemFont(ofSize: 12)

        draggableFileWrapper.addSubview(draggableFile)
        draggableFile.constrainEdgesToSuperview()
	}

	private func setup(url: URL) {
		draggableFile.fileUrl = url
		fileNameLabel.text = conversion.video.lastPathComponent
		fileSizeLabel.text = url.fileSizeFormatted

		// TODO: CustomButton doesn't correctly respect `.sendAction()`
		shareButton.sendAction(on: .leftMouseDown)
		shareButton.onAction = { _ in
			NSSharingService.share(items: [url as NSURL], from: self.shareButton)
		}
		copyButton.onAction = { _ in
			let pasteboard = NSPasteboard.general
			pasteboard.clearContents()
			pasteboard.writeObjects([url as NSURL])
		}

		saveAsButton.onAction = { _ in
		}
	}

	private func setupDropView() {
		let dropVideo = DropVideoViewController(dropLabelIsHidden: true)
		add(childController: dropVideo)
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

	override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
		return true
	}

	override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
		panel.delegate = self
		panel.dataSource = self
	}

	override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
		panel.dataSource = nil
		panel.delegate = nil
	}

	func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
		return 1
	}

	func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
		return gifUrl as NSURL
	}
}

extension ConversionCompletedViewController: QLPreviewPanelDelegate {
	func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> CGRect {
		return draggableFile.imageView?.boundsInScreenCoordinates ?? .zero
	}

	func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect: UnsafeMutablePointer<CGRect>!) -> Any! {
		return draggableFile.image
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
