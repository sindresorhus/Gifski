import Cocoa
import Quartz
import UserNotifications
import StoreKit

final class ConversionCompletedViewController: NSViewController {
	private let draggableFile = with(DraggableFile()) {
		$0.translatesAutoresizingMaskIntoConstraints = false
	}

	private let fileNameLabel = with(Label()) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.textColor = .labelColor
		$0.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
		$0.alignment = .center
		$0.maximumNumberOfLines = 1
		$0.cell?.lineBreakMode = .byTruncatingTail
	}

	private let fileSizeLabel = with(Label()) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.textColor = .secondaryLabelColor
		$0.font = .systemFont(ofSize: 12)
		$0.alignment = .center
	}

	private let infoContainer = with(NSStackView()) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.orientation = .vertical
	}

	private let imageContainer = with(NSStackView()) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.orientation = .vertical
	}

	private let buttonsContainer = with(NSStackView()) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.orientation = .horizontal
		$0.spacing = 20
	}

	private func createButton(title: String) -> NSButton {
		return with(NSButton()) {
			$0.translatesAutoresizingMaskIntoConstraints = false
			$0.title = title
			$0.bezelStyle = .texturedRounded
		}
	}

	private lazy var showInFinderButton = createButton(title: "Show in Finder")
	private lazy var shareButton = createButton(title: "Share")

	private var conversion: Gifski.Conversion!
	private var gifUrl: URL!

	convenience init(conversion: Gifski.Conversion, gifUrl: URL) {
		self.init()

		self.conversion = conversion
		self.gifUrl = gifUrl
	}

	override func loadView() {
		let wrapper = NSView(frame: CGRect(origin: .zero, size: CGSize(width: 360, height: 240)))
		wrapper.translatesAutoresizingMaskIntoConstraints = false

		infoContainer.addArrangedSubview(fileNameLabel)
		infoContainer.addArrangedSubview(fileSizeLabel)

		imageContainer.addArrangedSubview(draggableFile)
		imageContainer.addArrangedSubview(infoContainer)

		buttonsContainer.addArrangedSubview(showInFinderButton)
		buttonsContainer.addArrangedSubview(shareButton)

		wrapper.addSubview(imageContainer)
		wrapper.addSubview(buttonsContainer)

		NSLayoutConstraint.activate([
			wrapper.widthAnchor.constraint(equalToConstant: 360),
			imageContainer.widthAnchor.constraint(equalTo: wrapper.widthAnchor),
			infoContainer.widthAnchor.constraint(equalTo: imageContainer.widthAnchor),

			infoContainer.topAnchor.constraint(equalTo: draggableFile.bottomAnchor, constant: 18),
			imageContainer.topAnchor.constraint(greaterThanOrEqualTo: wrapper.topAnchor, constant: 32),

			draggableFile.centerXAnchor.constraint(equalTo: imageContainer.centerXAnchor),
			draggableFile.widthAnchor.constraint(equalToConstant: 96),

			fileNameLabel.widthAnchor.constraint(equalTo: infoContainer.widthAnchor),
			fileSizeLabel.widthAnchor.constraint(equalTo: infoContainer.widthAnchor),

			shareButton.heightAnchor.constraint(equalTo: buttonsContainer.heightAnchor),
			shareButton.widthAnchor.constraint(equalTo: showInFinderButton.widthAnchor),

			buttonsContainer.heightAnchor.constraint(equalToConstant: 30),
			buttonsContainer.topAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: 24),
			buttonsContainer.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
			buttonsContainer.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -32)
		])
		view = wrapper
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		let url = gifUrl!
		draggableFile.fileUrl = url
		fileNameLabel.text = conversion.video.lastPathComponent
		fileSizeLabel.text = url.fileSizeFormatted

		showInFinderButton.onAction = { _ in
			NSWorkspace.shared.activateFileViewerSelecting([url])
		}

		// TODO: CustomButton doesn't correctly respect `.sendAction()`
		shareButton.sendAction(on: .leftMouseDown)
		shareButton.onAction = { _ in
			NSSharingService.share(items: [url as NSURL], from: self.shareButton)
		}
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
