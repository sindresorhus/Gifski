import Cocoa

final class DraggableFile: NSImageView, NSDraggingSource {
	private var mouseDownEvent: NSEvent!

	var fileUrl: URL! {
		didSet {
			image = NSImage(byReferencing: fileUrl)
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		isEditable = false
		unregisterDraggedTypes()
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
		return .copy
	}

	override func mouseDown(with event: NSEvent) {
		mouseDownEvent = event
	}

	override func mouseDragged(with event: NSEvent) {
		let mouseDownPoint = mouseDownEvent.locationInWindow
		let dragPoint = event.locationInWindow
		let dragDistance = hypot(mouseDownPoint.x - dragPoint.x, mouseDownPoint.y - dragPoint.y)

		if dragDistance < 3 {
			return
		}

		guard let image = self.image else {
			return
		}

		let size = CGSize(width: 64, height: 64 * (image.size.height / image.size.width))

		guard let draggingImage = image.resize(withSize: size) else {
			return
		}

		let draggingItem = NSDraggingItem(pasteboardWriter: fileUrl as NSURL)
		let draggingFrameOrigin = convert(mouseDownPoint, from: nil)
		let draggingFrame = CGRect(origin: draggingFrameOrigin, size: draggingImage.size)
			.offsetBy(dx: -draggingImage.size.width / 2, dy: -draggingImage.size.height / 2)

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
