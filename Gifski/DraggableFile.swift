import Cocoa

final class DraggableFile: NSImageView {
	private var mouseDownEvent: NSEvent!
	private var heightConstraint: NSLayoutConstraint!

	var fileUrl: URL! {
		didSet {
			image = NSImage(byReferencing: fileUrl)

			heightConstraint.constant = image!.size.maxSize(size: 96).height
			updateConstraints()

			self.layer?.animateScaleMove(fromScale: 3.0, fromY: superview!.superview!.frame.height + frame.size.height)
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		heightConstraint = heightAnchor.constraint(equalToConstant: 0)

		isEditable = false
		unregisterDraggedTypes()

		wantsLayer = true

		NSLayoutConstraint.activate([
			heightConstraint
		])

		let sh = with(NSShadow()) {
			$0.shadowBlurRadius = 5.0
			$0.shadowColor = NSColor(named: NSColor.Name("ShadowColor"))
			$0.shadowOffset = CGSize(width: 0, height: 0)
		}

		shadow = sh
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func mouseDown(with event: NSEvent) {
		mouseDownEvent = event
	}

	override func mouseDragged(with event: NSEvent) {
		guard let image = self.image else {
			return
		}

		let size = image.size.maxSize(size: 96)

		let draggingItem = NSDraggingItem(pasteboardWriter: fileUrl as NSURL)
		let draggingFrame = CGRect(origin: CGPoint(x: (frame.size.width - size.width) / 2, y: (frame.size.height - size.height) / 2), size: size)
		draggingItem.draggingFrame = draggingFrame

		draggingItem.imageComponentsProvider = {
			let component = NSDraggingImageComponent(key: .icon)
			component.contents = image
			component.frame = CGRect(origin: .zero, size: draggingFrame.size)
			return [component]
		}

		beginDraggingSession(with: [draggingItem], event: mouseDownEvent, source: self)
	}
}

extension DraggableFile: NSDraggingSource {
	func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
		return .copy
	}
}
