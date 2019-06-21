import Cocoa
import Quartz

final class ConversionCompletedView: SSView {
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

	private var isConversionCompleted: Bool {
		return isHidden == false && fileUrl != nil
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

	var fileUrl: URL! {
		didSet {
			let url = fileUrl!
			draggableFile.fileUrl = url
			fileNameLabel.text = url.lastPathComponent
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
	}

	func show() {
		// We need to manually make self as the first responder, but when the view is hidden it is auto-removed
		window?.makeFirstResponder(self)

		fadeIn()
	}

	override func didAppear() {
		translatesAutoresizingMaskIntoConstraints = false

		infoContainer.addArrangedSubview(fileNameLabel)
		infoContainer.addArrangedSubview(fileSizeLabel)

		imageContainer.addArrangedSubview(draggableFile)
		imageContainer.addArrangedSubview(infoContainer)

		buttonsContainer.addArrangedSubview(showInFinderButton)
		buttonsContainer.addArrangedSubview(shareButton)

		addSubview(imageContainer)
		addSubview(buttonsContainer)

		// TODO: Improve the layout constraints. They are not very good.
		NSLayoutConstraint.activate([
			bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
			widthAnchor.constraint(equalToConstant: 300),
			centerXAnchor.constraint(equalTo: superview!.centerXAnchor),
			centerYAnchor.constraint(equalTo: superview!.centerYAnchor, constant: 5),

			imageContainer.topAnchor.constraint(equalTo: topAnchor),
			imageContainer.widthAnchor.constraint(equalTo: widthAnchor),

			infoContainer.topAnchor.constraint(equalTo: draggableFile.bottomAnchor, constant: 18),
			infoContainer.widthAnchor.constraint(equalTo: imageContainer.widthAnchor),

			buttonsContainer.topAnchor.constraint(equalTo: infoContainer.bottomAnchor, constant: 24),
			buttonsContainer.heightAnchor.constraint(equalToConstant: 30),
			buttonsContainer.centerXAnchor.constraint(equalTo: centerXAnchor),

			draggableFile.centerXAnchor.constraint(equalTo: centerXAnchor),
			draggableFile.widthAnchor.constraint(equalToConstant: 96),

			fileNameLabel.widthAnchor.constraint(equalTo: infoContainer.widthAnchor),
			fileSizeLabel.widthAnchor.constraint(equalTo: infoContainer.widthAnchor),

			showInFinderButton.heightAnchor.constraint(equalTo: buttonsContainer.heightAnchor),
			showInFinderButton.widthAnchor.constraint(equalToConstant: 110),

			shareButton.heightAnchor.constraint(equalTo: buttonsContainer.heightAnchor),
			shareButton.widthAnchor.constraint(equalTo: showInFinderButton.widthAnchor)
		])
	}
}

extension ConversionCompletedView: QLPreviewPanelDataSource {
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
		return fileUrl as NSURL
	}
}

extension ConversionCompletedView: QLPreviewPanelDelegate {
	func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> CGRect {
		return draggableFile.imageView?.boundsInScreenCoordinates ?? .zero
	}

	func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect: UnsafeMutablePointer<CGRect>!) -> Any! {
		return draggableFile.image
	}
}

extension ConversionCompletedView: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(quickLook(_:))?:
			return isConversionCompleted
		default:
			return true
		}
	}
}
