import Cocoa

// swiftlint:disable:next final_class
class DropView<CompletionType>: SSView {
	var onComplete: ((CompletionType) -> Void)?

	var dropView: NSView?

	var highlightColor: NSColor { .controlAccentColor }

	var isDropLabelHidden = false {
		didSet {
			dropView?.isHidden = isDropLabelHidden
		}
	}

	var acceptedTypes: [NSPasteboard.PasteboardType] {
		unimplemented()
	}

	private var isDraggingHighlighted = false {
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
		guard
			sender.draggingSourceOperationMask.contains(.copy),
			onEntered(sender)
		else {
			return []
		}

		isDraggingHighlighted = true
		return .copy
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
		sender.draggingPasteboard.fileURLs(types: Device.supportedVideoTypes).count == 1
	}

	override func onPerform(_ sender: NSDraggingInfo) -> Bool {
		guard
			let url = sender.draggingPasteboard.fileURLs(types: Device.supportedVideoTypes).first
		else {
			return false
		}

		onComplete?(url)
		return true
	}
}
