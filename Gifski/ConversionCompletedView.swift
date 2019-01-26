import Cocoa

class ConversionCompletedView: SSView {
	var margins = [CGFloat]()
	
	var fileUrl: URL? {
		didSet {
			draggableFile.fileUrl = fileUrl
			if let url = fileUrl {
				draggableFile.image = NSWorkspace.shared.icon(forFile: url.path)
				fileName = url.lastPathComponent
			}
		}
	}
	
	var fileName: String = "" {
		didSet {
			fileNameLabel.text = fileName
			fileNameLabel.sizeToFit()
			fileNameLabel.frame.origin.x = frame.size.width / 2 - fileNameLabel.frame.size.width / 2
		}
	}

	var fileSize: String = "" {
		didSet {
			fileSizeLabel.text = fileSize
			fileSizeLabel.sizeToFit()
			fileSizeLabel.frame.origin.x = frame.size.width / 2 - fileSizeLabel.frame.size.width / 2
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
		$0.frame = CGRect(x: 0, y: 0, width: 110, height: 30)
		$0.textColor = .appTheme
		$0.backgroundColor = .clear
		$0.borderWidth = 1
	}

	override init(frame: NSRect) {
		super.init(frame: frame)
		autoresizingMask = [.width, .height]
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	public func updateFileSize() {
		let formatter = ByteCountFormatter()
		formatter.zeroPadsFractionDigits = true
		
		var size : UInt64 = 0
		
		do {
			let attr = try FileManager.default.attributesOfItem(atPath: fileUrl!.path)
			let dict = attr as NSDictionary
			size = dict.fileSize()
		} catch {
			print("Error: \(error)")
		}
		
		fileSize = formatter.string(fromByteCount: Int64(size))
	}

	func layoutSubviews() {
		var height: CGFloat = 0

		for i in (0 ... subviews.count - 1).reversed() {
			let view = subviews[i]
			view.frame.origin.y = height + margins[i]
			height += view.frame.height + margins[i]
		}

		frame.size.height = height
	}
	
	func appendView(_ view: NSView, _ marginBottom: CGFloat = 0) {
		margins.append(marginBottom)
		addSubview(view)
	}

	override func didAppear() {
		appendView(fileSizeLabel, 16)
		
		draggableFile.frame = CGRect(x: frame.size.width / 2 - 64 / 2, y: 0, width: 64, height: 64)
		appendView(draggableFile, 8)
		
		appendView(fileNameLabel, 16)
		appendView(showInFinderButton)
		
		layoutSubviews()

		frame.centerY = superview!.frame.centerY
	}

	override func layout() {
		super.layout()
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
	}
}
