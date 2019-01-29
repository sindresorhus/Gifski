import Cocoa

final class DraggableFile: NSImageView, NSDraggingSource {
	var mouseDownEvent: NSEvent?

	var fileUrl: URL? {
		didSet {
			if let url = fileUrl {
				image = NSImage(byReferencing: url)
				image?.resizingMode = .stretch
			}
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		isEditable = false
		
		unregisterDraggedTypes()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
	}

	func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
		return .copy
	}

	override func mouseDown(with theEvent: NSEvent) {
		mouseDownEvent = theEvent
	}

	override func mouseDragged(with event: NSEvent) {
		let mouseDown = mouseDownEvent!.locationInWindow
		let dragPoint = event.locationInWindow
		let dragDistance = hypot(mouseDown.x - dragPoint.x, mouseDown.y - dragPoint.y)

		if dragDistance < 3 {
			return
		}

		guard let image = self.image else {
			return
		}
		
		let size = NSSize(width: 64, height: 64 * (image.size.height / image.size.width))
		
		if let draggingImage = image.resize(withSize: size) {
			let draggingItem = NSDraggingItem(pasteboardWriter: fileUrl! as NSURL)
			let draggingFrameOrigin = convert(mouseDown, from: nil)
			let draggingFrame = NSRect(origin: draggingFrameOrigin, size: draggingImage.size)
				.offsetBy(dx: -draggingImage.size.width / 2, dy: -draggingImage.size.height / 2)
			
			draggingItem.draggingFrame = draggingFrame
			
			draggingItem.imageComponentsProvider = {
				let component = NSDraggingImageComponent(key: NSDraggingItem.ImageComponentKey.icon)
				
				component.contents = image
				component.frame = NSRect(origin: NSPoint(), size: draggingFrame.size)
				return [component]
			}
			
			beginDraggingSession(with: [draggingItem], event: mouseDownEvent!, source: self)
		}
	}
}
