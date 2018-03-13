import Cocoa

/// TODO(sindresorhus): I plan to extract this into a separate package soon

@IBDesignable
public final class CircularProgress: NSView {
	private var lineWidth: Double = 2
	lazy var radius = bounds.midX * 0.8
	private var progressObserver: NSKeyValueObservation?

	private lazy var backgroundCircle = with(CAShapeLayer.circle(radius: Double(radius), center: bounds.center)) {
		$0.frame = bounds
		$0.fillColor = nil
		$0.lineWidth = CGFloat(lineWidth) / 2
		$0.strokeColor = color.with(alpha: 0.5).cgColor
	}

	private lazy var progressCircle = with(ProgressCircleShapeLayer(radius: Double(radius), center: bounds.center)) {
		$0.lineWidth = CGFloat(lineWidth)
	}

	private lazy var progressLabel = with(CATextLayer(text: "0%")) {
		$0.color = color
		$0.frame = bounds
		$0.fontSize = bounds.width * 0.2
		$0.position.y = bounds.midY * 0.25
		$0.alignmentMode = kCAAlignmentCenter
		$0.font = NSFont.helveticaNeueLight // Not using the system font as it has too much number width variance
	}

	@IBInspectable public var color: NSColor = .systemBlue {
		didSet {
			backgroundCircle.strokeColor = color.with(alpha: 0.5).cgColor
			progressCircle.strokeColor = color.cgColor
			progressLabel.foregroundColor = color.cgColor
		}
	}

	@IBInspectable public var progressValue: Double = 0 {
		didSet {
			// swiftlint:disable:next trailing_closure
			CALayer.animate(duration: 1, timingFunction: .easeOut, animations: {
				self.progressCircle.progress = self.progressValue
			})

			progressLabel.string = progressValue == 1 ? "✔" : "\(Int(progressValue * 100))%"

			// TODO: Figure out why I need to flush here to get the label to update
			CATransaction.flush()
		}
	}

	public var progress: Progress? {
		didSet {
			if let progress = progress {
				progressObserver = progress.observe(\.fractionCompleted) { sender, _ in
					self.progressValue = sender.fractionCompleted
				}
			}
		}
	}

	override public init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	required public init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	private func commonInit() {
		wantsLayer = true
		layer?.addSublayer(backgroundCircle)
		layer?.addSublayer(progressCircle)
		layer?.addSublayer(progressLabel)
	}

	public func resetProgress() {
		CALayer.withoutImplicitAnimations {
			progressCircle.progress = 0
		}

		progressLabel.string = "0%"
	}
}


extension CALayer {
	static func animate(
		duration: TimeInterval = 1,
		delay: TimeInterval = 0,
		timingFunction: CAMediaTimingFunction = .default,
		animations: @escaping (() -> Void),
		completion: (() -> Void)? = nil
	) {
		DispatchQueue.main.asyncAfter(duration: delay) {
			CATransaction.begin()
			CATransaction.setAnimationDuration(duration)

			if let completion = completion {
				CATransaction.setCompletionBlock(completion)
			}

			animations()
			CATransaction.commit()
		}
	}
}

extension NSFont {
	static let helveticaNeueLight = NSFont(name: "HelveticaNeue-Light", size: 0)
}

extension NSColor {
	func with(alpha: Double) -> NSColor {
		return withAlphaComponent(CGFloat(alpha))
	}
}

extension NSBezierPath {
	static func circle(radius: Double, center: CGPoint) -> NSBezierPath {
		let path = NSBezierPath()
		path.appendArc(
			withCenter: center,
			radius: CGFloat(radius),
			startAngle: 0,
			endAngle: 360
		)
		return path
	}

	/// For making a circle progress indicator
	static func progressCircle(radius: Double, center: CGPoint) -> NSBezierPath {
		let startAngle: CGFloat = 90
		let path = NSBezierPath()
		path.appendArc(
			withCenter: center,
			radius: CGFloat(radius),
			startAngle: startAngle,
			endAngle: startAngle - 360,
			clockwise: true
		)
		return path
	}
}

extension CAShapeLayer {
	static func circle(radius: Double, center: CGPoint) -> CAShapeLayer {
		return CAShapeLayer(path: NSBezierPath.circle(radius: radius, center: center))
	}

	convenience init(path: NSBezierPath) {
		self.init()
		self.path = path.cgPath
	}
}

extension CATextLayer {
	/// Initializer with better defaults
	convenience init(text: String, fontSize: Double? = nil, color: NSColor? = nil) {
		self.init()
		string = text
		if let fontSize = fontSize {
			self.fontSize = CGFloat(fontSize)
		}
		self.color = color
		implicitAnimations = false
		setAutomaticContentsScale()
	}

	var color: NSColor? {
		get {
			guard let color = foregroundColor else {
				return nil
			}
			return NSColor(cgColor: color)
		}
		set {
			foregroundColor = newValue?.cgColor
		}
	}
}

final class ProgressCircleShapeLayer: CAShapeLayer {
	convenience init(radius: Double, center: CGPoint) {
		self.init()
		fillColor = nil
		lineCap = kCALineCapRound
		path = NSBezierPath.progressCircle(radius: radius, center: center).cgPath
	}

	var progress: Double {
		get {
			return Double(strokeEnd)
		}
		set {
			strokeEnd = CGFloat(newValue)
		}
	}
}
