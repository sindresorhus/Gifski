import Cocoa

final class ConversionCompletedView: SSView {
	private let draggableFile = DraggableFile()

	private let fileNameLabel = with(Label()) {
		$0.textColor = .secondaryLabelColor
		$0.font = .boldSystemFont(ofSize: 14)
	}

	private let fileSizeLabel = with(Label()) {
		$0.textColor = .secondaryLabelColor
		$0.font = .systemFont(ofSize: 12)
	}

	private lazy var showInFinderButton = with(CustomButton()) {
		$0.title = "Show in Finder"
		$0.textColor = .appTheme
		$0.backgroundColor = .clear
		$0.borderWidth = 1
	}

	var fileUrl: URL! {
		didSet {
			let url = fileUrl!
			draggableFile.fileUrl = url
			fileNameLabel.text = url.lastPathComponent
			fileSizeLabel.text = url.formattedFileSize()

			showInFinderButton.onAction = { _ in
				NSWorkspace.shared.activateFileViewerSelecting([url])
			}
		}
	}

	func show() {
		fadeIn()
	}

	override func didAppear() {
		translatesAutoresizingMaskIntoConstraints = false

		fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(fileNameLabel)

		fileSizeLabel.translatesAutoresizingMaskIntoConstraints = false
		addSubview(fileSizeLabel)

		draggableFile.translatesAutoresizingMaskIntoConstraints = false
		addSubview(draggableFile)

		showInFinderButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(showInFinderButton)

		NSLayoutConstraint.activate([
			bottomAnchor.constraint(equalTo: showInFinderButton.bottomAnchor),
			widthAnchor.constraint(equalToConstant: 110),
			centerXAnchor.constraint(equalTo: superview!.centerXAnchor),
			centerYAnchor.constraint(equalTo: superview!.centerYAnchor),

			draggableFile.centerXAnchor.constraint(equalTo: centerXAnchor),
			draggableFile.topAnchor.constraint(equalTo: topAnchor),
			draggableFile.heightAnchor.constraint(equalToConstant: 96),
			draggableFile.widthAnchor.constraint(equalToConstant: 96),

			fileNameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			fileNameLabel.topAnchor.constraint(equalTo: draggableFile.bottomAnchor, constant: 8),

			fileSizeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			fileSizeLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor),

			showInFinderButton.heightAnchor.constraint(equalToConstant: 30),
			showInFinderButton.widthAnchor.constraint(equalToConstant: 110),
			showInFinderButton.topAnchor.constraint(equalTo: fileSizeLabel.bottomAnchor, constant: 16)
		])
	}
}
