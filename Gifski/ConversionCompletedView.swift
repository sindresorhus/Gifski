import Cocoa

final class ConversionCompletedView: SSView {
	var fileUrl: URL? {
		didSet {
			draggableFile.fileUrl = fileUrl
			if let url = fileUrl {
				draggableFile.image = NSWorkspace.shared.icon(forFile: url.path)
				fileName = url.lastPathComponent

				showInFinderButton.onAction = { _ in
					NSWorkspace.shared.activateFileViewerSelecting([url])
				}
			}
		}
	}

	var fileName: String = "" {
		didSet {
			fileNameLabel.text = fileName
		}
	}

	var fileSize: String = "" {
		didSet {
			fileSizeLabel.text = fileSize
		}
	}

	private let fileNameLabel = with(Label()) {
		$0.textColor = NSColor.secondaryLabelColor
		$0.font = NSFont.boldSystemFont(ofSize: 14.0)
	}

	private let fileSizeLabel = with(Label()) {
		$0.textColor = NSColor.secondaryLabelColor
	}

	public let draggableFile = DraggableFile()

	lazy var showInFinderButton = with(CustomButton()) {
		$0.title = "Show in Finder"
		$0.textColor = .appTheme
		$0.backgroundColor = .clear
		$0.borderWidth = 1
	}

	override init(frame: NSRect) {
		super.init(frame: frame)
	}
	
	public func show() {
		fileSize = fileUrl!.getFileSize()
		fadeIn()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func didAppear() {
		translatesAutoresizingMaskIntoConstraints = false
		
		addSubview(fileNameLabel)
		fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
		
		addSubview(fileSizeLabel)
		fileSizeLabel.translatesAutoresizingMaskIntoConstraints = false
		
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
			draggableFile.heightAnchor.constraint(equalToConstant: 64),
			draggableFile.widthAnchor.constraint(equalToConstant: 64),
			
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
