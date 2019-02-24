import Cocoa

final class DraggableFile: NSImageView {
	private var mouseDownEvent: NSEvent!

	var fileUrl: URL! {
		didSet {
			image = NSImage(byReferencing: fileUrl)
			animateY()
			animateScale()
		}
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		isEditable = false
		unregisterDraggedTypes()

		superview?.wantsLayer = true
		wantsLayer = true

		let sh = NSShadow()
		sh.shadowBlurRadius = 5.0
		sh.shadowOffset = CGSize(width: 0, height: 0)
		sh.shadowColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 0.5)
		shadow = sh
	}
	
	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func mouseDown(with event: NSEvent) {
		mouseDownEvent = event
	}

	func animateY() {
		let springAnimation = CASpringAnimation(keyPath: "position")

		springAnimation.damping = 15
		springAnimation.mass = 0.2
		springAnimation.initialVelocity = 1.0
		springAnimation.duration = springAnimation.settlingDuration

		guard let pos = self.layer?.position else {
			return
		}

		springAnimation.fromValue = CGPoint(x: pos.x, y: superview!.superview!.frame.height + frame.size.height)
		springAnimation.toValue = pos

		self.layer?.add(springAnimation, forKey: "position")
	}
	
	func animateScale() {
		let springAnimation = CASpringAnimation(keyPath: "transform.scale")
		
		springAnimation.damping = 15
		springAnimation.mass = 0.9
		springAnimation.initialVelocity = 1.0
		springAnimation.duration = springAnimation.settlingDuration
		
		springAnimation.fromValue = 5.0
		springAnimation.toValue = 1.0
		
		self.layer?.add(springAnimation, forKey: "scale")
	}

	
	override func mouseDragged(with event: NSEvent) {
		guard let image = self.image else {
			return
		}

		let size = CGSize(width: 96, height: 96 * (image.size.height / image.size.width))

		let draggingItem = NSDraggingItem(pasteboardWriter: fileUrl as NSURL)
		let draggingFrame = CGRect(origin: NSPoint(x: 0, y: (frame.size.height - size.height) / 2), size: size)
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
