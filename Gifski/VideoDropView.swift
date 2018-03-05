import Cocoa

class DropView: SSView {
	var dropText: String? {
		didSet {
			if let text = dropText {
				dropLabel.text = text
			}
		}
	}

	lazy private var dropLabel: Label = {
		let label = Label()
		label.textColor = .systemGray
		label.font = .systemFont(ofSize: 14, weight: .light)
		return label
	}()

	var highlightColor: NSColor {
		return .selectedControlColor
	}

	var acceptedTypes: [NSPasteboard.PasteboardType] {
		unimplemented()
	}

	private var isDraggingHighlighted: Bool = false {
		didSet {
			needsDisplay = true
			dropLabel.animateTextColor(to: isDraggingHighlighted ? highlightColor : .disabledControlTextColor)
		}
	}

	override func didAppear() {
		addSubviewToCenter(dropLabel)
	}

	override init(frame: NSRect) {
		super.init(frame: frame)
		autoresizingMask = [.width, .height]
		registerForDraggedTypes(acceptedTypes)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)

		if isDraggingHighlighted {
			highlightColor.set()
			let path = NSBezierPath(rect: bounds)
			path.lineWidth = 8
			path.stroke()
		}
	}

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		if sender.draggingSourceOperationMask().contains(.copy) && onEntered(sender) {
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

final class VideoDropView: DropView {
	/// TODO: Any way to make this generic so we can have it in DropView instead?
	var onComplete: (([URL]) -> Void)?

	override var highlightColor: NSColor {
		return .appTheme
	}

	override var acceptedTypes: [NSPasteboard.PasteboardType] {
		return [.fileURL]
	}

	override func onEntered(_ sender: NSDraggingInfo) -> Bool {
		return sender.fileURLs(types: System.supportedVideoTypes).count == 1
	}

	override func onPerform(_ sender: NSDraggingInfo) -> Bool {
		if let url = sender.fileURLs(types: System.supportedVideoTypes).first {
			onComplete?([url])
			return true
		}

		return false
	}
}
