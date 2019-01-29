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

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	public func updateFileSize() {
		let formatter = ByteCountFormatter()
		formatter.zeroPadsFractionDigits = true

		var size: UInt64 = 0

		do {
			let attr = try FileManager.default.attributesOfItem(atPath: fileUrl!.path)
			let dict = attr as NSDictionary
			size = dict.fileSize()
		} catch {
			print("Error: \(error)")
		}

		fileSize = formatter.string(fromByteCount: Int64(size))
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
			
			fileSizeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			fileSizeLabel.topAnchor.constraint(equalTo: topAnchor),
			
			draggableFile.centerXAnchor.constraint(equalTo: centerXAnchor),
			draggableFile.topAnchor.constraint(equalTo: fileSizeLabel.bottomAnchor, constant: 24),
			draggableFile.heightAnchor.constraint(equalToConstant: 64),
			draggableFile.widthAnchor.constraint(equalToConstant: 64),
			
			fileNameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
			fileNameLabel.topAnchor.constraint(equalTo: draggableFile.bottomAnchor, constant: 8),
			
			showInFinderButton.heightAnchor.constraint(equalToConstant: 30),
			showInFinderButton.widthAnchor.constraint(equalToConstant: 110),
			showInFinderButton.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 24)
		])
	}
}
