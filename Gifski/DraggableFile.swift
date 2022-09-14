import Cocoa

final class DraggableFile: NSImageView {
	var thumbnailFrameSize = 84.0 {
		// FIXME: This is actually never set.
		didSet {
			guard let image else {
				return
			}

			let height = image.size.aspectFit(to: thumbnailFrameSize).height
			heightAnchor.constraint(equalToConstant: height).isActive = true
		}
	}

	var fileUrl: URL? {
		didSet {
			guard
				let fileUrl,
				let image = NSImage(contentsOf: fileUrl)
			else {
				return
			}

			self.image = image

			let height = image.size.aspectFit(to: thumbnailFrameSize).height
			heightAnchor.constraint(equalToConstant: height).isActive = true
		}
	}

	var imageView: NSView? { subviews.first }

	override init(frame: CGRect) {
		super.init(frame: frame)

		wantsLayer = true
		isEditable = false

		shadow = with(NSShadow()) {
			$0.shadowBlurRadius = 5
			$0.shadowColor = NSColor(named: "ShadowColor")
			$0.shadowOffset = .zero
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func mouseDragged(with event: NSEvent) {
		guard
			let fileUrl,
			let image
		else {
			return
		}

		// swiftlint:disable:next legacy_objc_type
		let draggingItem = NSDraggingItem(pasteboardWriter: fileUrl as NSURL)
		let draggingFrame = image.size.aspectFit(to: thumbnailFrameSize).cgRect.centered(in: bounds)
		draggingItem.setDraggingFrame(draggingFrame, contents: image)
		beginDraggingSession(with: [draggingItem], event: event, source: self)
	}
}

extension DraggableFile: NSDraggingSource {
	func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
