import Cocoa

public final class HoverView: NSView {
	enum Event {
		case entered, exited
	}

	typealias HoverClosure = ((Event) -> Void)

	/**
	Initialize the progress view with a width/height of the given `size`.
	*/
	public convenience init(size: Double) {
		self.init(frame: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
	}

	private var trackingArea: NSTrackingArea?

	override public func updateTrackingAreas() {
		if let oldTrackingArea = trackingArea {
			removeTrackingArea(oldTrackingArea)
		}
		guard onHover != nil else {
			return
		}
		let newTrackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self, userInfo: nil)
		addTrackingArea(newTrackingArea)
		self.trackingArea = newTrackingArea
	}

	var onHover: HoverClosure? {
		didSet {
			updateTrackingAreas()
		}
	}

	override public func mouseEntered(with event: NSEvent) {
		onHover?(.entered)
	}

	override public func mouseExited(with event: NSEvent) {
		onHover?(.exited)
	}
}
