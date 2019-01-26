import Cocoa

class DraggableFile: NSImageView, NSDraggingSource, NSFilePromiseProviderDelegate {
	/// Holds the last mouse down event, to track the drag distance.
	var mouseDownEvent: NSEvent?

	var fileUrl: URL?

	public func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
		return fileUrl!.lastPathComponent
	}

	public func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {

		do {
			try FileManager.default.copyItem(at: fileUrl!, to: url)
			completionHandler(nil)
		} catch let error {
			print(error)
			completionHandler(error)
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)

		// Assure editable is set to true, to enable drop capabilities.
		isEditable = true
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)

		// Assure editable is set to true, to enable drop capabilities.
		isEditable = true
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
	}

	func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
		return .copy
	}

	func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation: NSDragOperation) {
	}

	// Track mouse down events and safe the to the poperty.
	override func mouseDown(with theEvent: NSEvent) {
		mouseDownEvent = theEvent
	}

	// Track mouse dragged events to handle dragging sessions.
	override func mouseDragged(with event: NSEvent) {
		// Calculate the dragging distance...
		let mouseDown = mouseDownEvent!.locationInWindow
		let dragPoint = event.locationInWindow
		let dragDistance = hypot(mouseDown.x - dragPoint.x, mouseDown.y - dragPoint.y)

		// Cancel the dragging session in case of an accidental drag.
		if dragDistance < 3 {
			return
		}

		guard let image = self.image else {
			return
		}

		// Do some math to properly resize the given image.
		let size = NSSize(width: log10(image.size.width) * 30, height: log10(image.size.height) * 30)

		if let draggingImage = image.resize(withSize: size) {
			// Create a new NSDraggingItem with the image as content.
			let draggingItem = NSDraggingItem(pasteboardWriter: NSFilePromiseProvider(fileType: "public.data", delegate: self))

			// Calculate the mouseDown location from the window's coordinate system to the
			// ImageView's coordinate system, to use it as origin for the dragging frame.
			let draggingFrameOrigin = convert(mouseDown, from: nil)
			// Build the dragging frame and offset it by half the image size on each axis
			// to center the mouse cursor within the dragging frame.
			let draggingFrame = NSRect(origin: draggingFrameOrigin, size: draggingImage.size)
				.offsetBy(dx: -draggingImage.size.width / 2, dy: -draggingImage.size.height / 2)

			// Assign the dragging frame to the draggingFrame property of our dragging item.
			draggingItem.draggingFrame = draggingFrame

			// Provide the components of the dragging image.
			draggingItem.imageComponentsProvider = {
				let component = NSDraggingImageComponent(key: NSDraggingItem.ImageComponentKey.icon)

				component.contents = image
				component.frame = NSRect(origin: NSPoint(), size: draggingFrame.size)
				return [component]
			}

			// Begin actual dragging session. Woohow!
			beginDraggingSession(with: [draggingItem], event: mouseDownEvent!, source: self)
		}
	}
}
