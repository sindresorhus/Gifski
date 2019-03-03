import Cocoa

final class DraggableFile: NSImageView {
	private var mouseDownEvent: NSEvent!

	var fileUrl: URL! {
		didSet {
			image = NSImage(byReferencing: fileUrl)

			NSLayoutConstraint.activate([
				heightAnchor.constraint(equalToConstant: max(96 * (image!.size.height / image!.size.width), 96))
			])

			animate()
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		isEditable = false
		unregisterDraggedTypes()

		wantsLayer = true

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

	func animate() {
		let springAnimation = CASpringAnimation(keyPath: #keyPath(CALayer.transform))

		var tr = CATransform3DIdentity
		tr = CATransform3DTranslate(tr, bounds.size.width / 2, superview!.superview!.frame.height + frame.size.height, 0)
		tr = CATransform3DScale(tr, 3.0, 3.0, 1)
		tr = CATransform3DTranslate(tr, -bounds.size.width / 2, -bounds.size.height / 2, 0)

		springAnimation.damping = 15
		springAnimation.mass = 0.9
		springAnimation.initialVelocity = 1.0
		springAnimation.duration = springAnimation.settlingDuration

		springAnimation.fromValue = NSValue(caTransform3D: tr)
		springAnimation.toValue = NSValue(caTransform3D: CATransform3DIdentity)

		self.layer?.add(springAnimation, forKey: "")
	}

	override func mouseDragged(with event: NSEvent) {
		guard let image = self.image else {
			return
		}

		var width = image.size.width
		var height = image.size.height

		if width > 96 {
			width = 96
			height = 96 * (image.size.height / image.size.width)
		}

		if height > 96 {
			height = 96
			width = 96 * (image.size.width / image.size.height)
		}

		let size = CGSize(width: width, height: height)

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
