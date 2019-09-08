import Cocoa

final class DraggableFile: NSImageView {
	private let imageMaxSize: CGFloat = 84

	var fileUrl: URL? {
		didSet {
			guard
				let fileUrl = self.fileUrl,
				let image = NSImage(contentsOf: fileUrl)
			else {
				return
			}

			self.image = image

			let height = image.size.aspectFit(to: imageMaxSize).height
			heightAnchor.constraint(equalToConstant: height).isActive = true
		}
	}

	var imageView: NSView? {
		return subviews.first
	}

	override init(frame: CGRect) {
		super.init(frame: frame)

		wantsLayer = true
		isEditable = false

		shadow = with(NSShadow()) {
			$0.shadowBlurRadius = 5
			$0.shadowColor = NSColor(named: "ShadowColor")
			$0.shadowOffset = CGSize(width: 0, height: 0)
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func mouseDragged(with event: NSEvent) {
		guard
			let fileUrl = self.fileUrl,
			let image = self.image
		else {
			return
		}

		let draggingItem = NSDraggingItem(pasteboardWriter: fileUrl as NSURL)
		let draggingFrame = image.size.aspectFit(to: imageMaxSize).cgRect.centered(in: bounds)
		draggingItem.setDraggingFrame(draggingFrame, contents: image)
		beginDraggingSession(with: [draggingItem], event: event, source: self)
	}
}

extension DraggableFile: NSDraggingSource {
	func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
		return .copy
	}
}
