import Cocoa

public final class HoverView: NSView {
	public enum Event {
		case entered
		case exited
	}

	public typealias HoverClosure = ((Event) -> Void)

	private var trackingArea: NSTrackingArea?

	override public func updateTrackingAreas() {
		if let oldTrackingArea = trackingArea {
			removeTrackingArea(oldTrackingArea)
		}

		guard onHover != nil else {
			return
		}

		let newTrackingArea = NSTrackingArea(
			rect: bounds,
			options: [
				.mouseEnteredAndExited,
				.activeInActiveApp
			],
			owner: self,
			userInfo: nil
		)

		addTrackingArea(newTrackingArea)
		trackingArea = newTrackingArea
	}

	public var onHover: HoverClosure? {
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
