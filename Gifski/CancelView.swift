import Cocoa

@IBDesignable
public final class CancelView: NSView {
	private lazy var radius = bounds.midX * 0.8

	private lazy var backgroundCircle = with(CAShapeLayer.circle(radius: Double(radius), center: bounds.center)) {
		$0.frame = bounds
		$0.fillColor = nil
	}

	override public init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	var timeout: TimeInterval = 2

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
		backgroundCircle.transform = CATransform3DMakeScale(0, 0, 1)
		layer?.addSublayer(backgroundCircle)
	}

	private enum AnimationState {
		case idle, growing, shrinking
	}

	private var animationState: AnimationState = .idle

	func grow() {
		guard [.idle, .shrinking].contains(animationState) else {
			return
		}
		animationState = .growing

		CALayer.animate(duration: timeout,
						timingFunction: .easeIn,
						animations: {
							self.backgroundCircle.transform = CATransform3DMakeScale(1, 1, 1)
						}, completion: {
							self.animationState = .idle
						}
		)
	}

	func shrink() {
		guard [.idle, .growing].contains(animationState) else {
			return
		}
		animationState = .shrinking

		CALayer.animate(duration: 0.1,
						timingFunction: .easeIn,
						animations: {
							self.backgroundCircle.transform = CATransform3DMakeScale(0, 0, 1)
						}, completion: {
							self.animationState = .idle
						}
		)
	}
}
