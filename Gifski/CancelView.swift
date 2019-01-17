import Cocoa

@IBDesignable
public final class CancelView: NSView {
	private lazy var backgroundCircle: CAShapeLayer = {
		let frame = bounds
		let path = NSBezierPath()
		path.move(to: NSPoint(x: frame.minX + 0.26131 * frame.width, y: frame.minY + 0.77524 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.25682 * frame.width, y: frame.minY + 0.77072 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.26131 * frame.width, y: frame.minY + 0.77524 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.25958 * frame.width, y: frame.minY + 0.77350 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.21875 * frame.width, y: frame.minY + 0.73242 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.24588 * frame.width, y: frame.minY + 0.75971 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.21875 * frame.width, y: frame.minY + 0.73242 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.46034 * frame.width, y: frame.minY + 0.48933 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.21875 * frame.width, y: frame.minY + 0.73242 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.33741 * frame.width, y: frame.minY + 0.61302 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.22801 * frame.width, y: frame.minY + 0.25556 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.34078 * frame.width, y: frame.minY + 0.36903 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.22801 * frame.width, y: frame.minY + 0.25556 * frame.height))
		path.line(to: NSPoint(x: frame.minX + 0.27056 * frame.width, y: frame.minY + 0.21274 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.50289 * frame.width, y: frame.minY + 0.44651 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.27056 * frame.width, y: frame.minY + 0.21274 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.38334 * frame.width, y: frame.minY + 0.32621 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.72944 * frame.width, y: frame.minY + 0.21856 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.62028 * frame.width, y: frame.minY + 0.32840 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.72944 * frame.width, y: frame.minY + 0.21856 * frame.height))
		path.line(to: NSPoint(x: frame.minX + 0.77199 * frame.width, y: frame.minY + 0.26138 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.54545 * frame.width, y: frame.minY + 0.48933 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.77199 * frame.width, y: frame.minY + 0.26138 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.66283 * frame.width, y: frame.minY + 0.37122 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.78125 * frame.width, y: frame.minY + 0.72659 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.66629 * frame.width, y: frame.minY + 0.61092 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.78125 * frame.width, y: frame.minY + 0.72659 * frame.height))
		path.line(to: NSPoint(x: frame.minX + 0.73869 * frame.width, y: frame.minY + 0.76941 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.50289 * frame.width, y: frame.minY + 0.53215 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.73869 * frame.width, y: frame.minY + 0.76941 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.62373 * frame.width, y: frame.minY + 0.65374 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.26133 * frame.width, y: frame.minY + 0.77522 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.37997 * frame.width, y: frame.minY + 0.65584 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.26131 * frame.width, y: frame.minY + 0.77524 * frame.height))
		path.line(to: NSPoint(x: frame.minX + 0.26131 * frame.width, y: frame.minY + 0.77524 * frame.height))
		path.close()
		path.move(to: NSPoint(x: frame.minX + 1.00000 * frame.width, y: frame.minY + 0.50000 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.50000 * frame.width, y: frame.minY + 0.00000 * frame.height), controlPoint1: NSPoint(x: frame.minX + 1.00000 * frame.width, y: frame.minY + 0.22386 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.77614 * frame.width, y: frame.minY + 0.00000 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.17498 * frame.width, y: frame.minY + 0.12004 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.37591 * frame.width, y: frame.minY + 0.00000 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.26238 * frame.width, y: frame.minY + 0.04520 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.00000 * frame.width, y: frame.minY + 0.50000 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.06788 * frame.width, y: frame.minY + 0.21174 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.00000 * frame.width, y: frame.minY + 0.34794 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 0.50000 * frame.width, y: frame.minY + 1.00000 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.00000 * frame.width, y: frame.minY + 0.77614 * frame.height), controlPoint2: NSPoint(x: frame.minX + 0.22386 * frame.width, y: frame.minY + 1.00000 * frame.height))
		path.curve(to: NSPoint(x: frame.minX + 1.00000 * frame.width, y: frame.minY + 0.50000 * frame.height), controlPoint1: NSPoint(x: frame.minX + 0.77614 * frame.width, y: frame.minY + 1.00000 * frame.height), controlPoint2: NSPoint(x: frame.minX + 1.00000 * frame.width, y: frame.minY + 0.77614 * frame.height))
		path.close()

		return CAShapeLayer(path: path)
	}()

	override public init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	/**
	Initialize the cancel view with a width/height of the given `size` and the provided `timeout`.
	*/
	public convenience init(size: Double) {
		self.init(frame: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
	}

	/**
	Color of the circular progress view.
	
	Defaults to the user's accent color. For High Sierra and below it uses a fallback color.
	*/
	@IBInspectable public var color: NSColor = .controlAccentColorPolyfill {
		didSet {
			needsDisplay = true
		}
	}

	override public func updateLayer() {
		backgroundCircle.fillColor = color.cgColor
	}

	private func commonInit() {
		wantsLayer = true
		layer?.addSublayer(backgroundCircle)
	}
}
