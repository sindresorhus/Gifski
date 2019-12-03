import Cocoa

class DropView<CompletionType>: SSView {
	var onComplete: ((CompletionType) -> Void)?

	var dropText: String? {
		didSet {
			if let text = dropText {
				dropLabel.isHidden = false
				dropLabel.text = text
			} else {
				dropLabel.isHidden = true
			}
		}
	}

	var dropView: NSView?

	private let dropLabel = with(Label()) {
		$0.textColor = .secondaryLabelColor
		$0.font = NSFont.systemFont(ofSize: 14)
	}

	var highlightColor: NSColor { .controlAccentColorPolyfill }

	var isDropLabelHidden: Bool = false {
		didSet {
			dropLabel.isHidden = isDropLabelHidden
			dropView?.isHidden = isDropLabelHidden
		}
	}

	func fadeInVideoDropLabel() {
		dropLabel.fadeIn()
		dropView?.fadeIn()
	}

	var acceptedTypes: [NSPasteboard.PasteboardType] {
		unimplemented()
	}

	private var isDraggingHighlighted: Bool = false {
		didSet {
			needsDisplay = true
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		autoresizingMask = [.width, .height]
		registerForDraggedTypes(acceptedTypes)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func didAppear() {
		addSubviewToCenter(dropLabel)

		if let dropView = dropView {
			addSubviewToCenter(dropView)
		}
	}

	override func layout() {
		super.layout()

		if let bounds = superview?.bounds {
			frame = bounds
		}
	}

	override func draw(_ dirtyRect: CGRect) {
		super.draw(dirtyRect)

		// We only draw it when the drop view controller is the main view controller.
		if window?.contentViewController is VideoDropViewController {
			Constants.backgroundImage.draw(in: dirtyRect)
		}

		if isDraggingHighlighted {
			highlightColor.set()
			let path = NSBezierPath(rect: bounds)
			path.lineWidth = 8
			path.stroke()
		}
	}

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		if sender.draggingSourceOperationMask.contains(.copy) && onEntered(sender) {
			isDraggingHighlighted = true
			return .copy
		} else {
			return []
		}
	}

	override func draggingExited(_ sender: NSDraggingInfo?) {
		isDraggingHighlighted = false
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		isDraggingHighlighted = false
		return onPerform(sender)
	}

	func onEntered(_ sender: NSDraggingInfo) -> Bool {
		unimplemented()
	}

	func onPerform(_ sender: NSDraggingInfo) -> Bool {
		unimplemented()
	}
}

final class VideoDropView: DropView<URL> {
	override var highlightColor: NSColor { .themeColor }

	override var acceptedTypes: [NSPasteboard.PasteboardType] { [.fileURL] }

	override func onEntered(_ sender: NSDraggingInfo) -> Bool {
		sender.draggingPasteboard.fileURLs(types: System.supportedVideoTypes).count == 1
	}

	override func onPerform(_ sender: NSDraggingInfo) -> Bool {
		if let url = sender.draggingPasteboard.fileURLs(types: System.supportedVideoTypes).first {
			onComplete?(url)
			return true
		}

		return false
	}
}
