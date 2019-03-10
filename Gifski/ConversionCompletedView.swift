import Cocoa

final class ConversionCompletedView: SSView {
	private let draggableFile = DraggableFile()

	private let fileNameLabel = with(Label()) {
		$0.textColor = .secondaryLabelColor
		$0.font = .boldSystemFont(ofSize: 14)
		$0.alignment = .center
	}

	private let fileSizeLabel = with(Label()) {
		$0.textColor = .secondaryLabelColor
		$0.font = .systemFont(ofSize: 12)
		$0.alignment = .center
	}

	private let infoContainer = with(NSStackView()) {
		$0.orientation = .vertical
	}

	private let imageContainer = with(NSStackView()) {
		$0.orientation = .vertical
	}

	private let buttonsContainer = with(NSStackView()) {
		$0.orientation = .horizontal
	}

	private lazy var showInFinderButton = with(CustomButton()) {
		$0.title = "Show in Finder"
		$0.textColor = .appTheme
		$0.backgroundColor = .clear
		$0.borderWidth = 1
	}

	private lazy var shareButton = with(CustomButton()) {
		$0.title = "Share"
		$0.textColor = .appTheme
		$0.backgroundColor = .clear
		$0.borderWidth = 1
	}

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
				NSSharingService.share(content: [url] as [AnyObject], from: self.shareButton)
			}
		}
	}

	func show() {
		fadeIn()
	}

	override func didAppear() {
		translatesAutoresizingMaskIntoConstraints = false

		infoContainer.translatesAutoresizingMaskIntoConstraints = false
		imageContainer.translatesAutoresizingMaskIntoConstraints = false
		draggableFile.translatesAutoresizingMaskIntoConstraints = false
		fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
		showInFinderButton.translatesAutoresizingMaskIntoConstraints = false
		shareButton.translatesAutoresizingMaskIntoConstraints = false
		fileSizeLabel.translatesAutoresizingMaskIntoConstraints = false
		buttonsContainer.translatesAutoresizingMaskIntoConstraints = false

		fileNameLabel.maximumNumberOfLines = 1
		fileNameLabel.cell?.lineBreakMode = .byTruncatingTail

		infoContainer.addArrangedSubview(fileNameLabel)
		infoContainer.addArrangedSubview(fileSizeLabel)

		imageContainer.addArrangedSubview(draggableFile)
		imageContainer.addArrangedSubview(infoContainer)

		buttonsContainer.addArrangedSubview(showInFinderButton)
		buttonsContainer.addArrangedSubview(shareButton)

		addSubview(imageContainer)
		addSubview(buttonsContainer)

		NSLayoutConstraint.activate([
			bottomAnchor.constraint(equalTo: buttonsContainer.bottomAnchor),
			widthAnchor.constraint(equalTo: buttonsContainer.widthAnchor),

			centerXAnchor.constraint(equalTo: superview!.centerXAnchor),
			centerYAnchor.constraint(equalTo: superview!.centerYAnchor),

			imageContainer.topAnchor.constraint(equalTo: topAnchor),
			imageContainer.widthAnchor.constraint(equalTo: widthAnchor),

			infoContainer.topAnchor.constraint(equalTo: draggableFile.bottomAnchor, constant: 16),
			infoContainer.widthAnchor.constraint(equalTo: imageContainer.widthAnchor),

			buttonsContainer.topAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: 16),
			buttonsContainer.heightAnchor.constraint(equalToConstant: 30),
			buttonsContainer.widthAnchor.constraint(equalToConstant: 228),

			draggableFile.centerXAnchor.constraint(equalTo: centerXAnchor),
			draggableFile.widthAnchor.constraint(equalToConstant: 96),

			fileNameLabel.widthAnchor.constraint(equalTo: infoContainer.widthAnchor),
			fileSizeLabel.widthAnchor.constraint(equalTo: infoContainer.widthAnchor),

			showInFinderButton.heightAnchor.constraint(equalTo: buttonsContainer.heightAnchor),
			showInFinderButton.widthAnchor.constraint(equalToConstant: 110),

			shareButton.heightAnchor.constraint(equalTo: buttonsContainer.heightAnchor),
			shareButton.widthAnchor.constraint(equalToConstant: 110)
		])
	}
}
