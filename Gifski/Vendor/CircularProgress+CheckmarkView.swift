import Cocoa

final class CheckmarkView: NSView {
	// MARK: - NSView

	override init(frame frameRect: CGRect) {
		super.init(frame: frameRect)
		commonInit()
	}

	required init?(coder decoder: NSCoder) {
		super.init(coder: decoder)
		commonInit()
	}

	override var isHidden: Bool {
		didSet {
			guard isHidden != oldValue else {
				return
			}

			if isHidden {
				stopAnimation()
			} else {
				startAnimation()
			}
		}
	}

	// MARK: - CheckmarkView

	private let animationDuration: TimeInterval = 0.5

	var color: NSColor = .controlAccentColorPolyfill {
		didSet {
			shapeLayer.strokeColor = color.cgColor
		}
	}

	var lineWidth: CGFloat = 2 {
		didSet {
			shapeLayer.lineWidth = lineWidth
		}
	}

	private func commonInit() {
		wantsLayer = true
		layer?.addSublayer(shapeLayer)
		stopAnimation()
	}

	private lazy var shapeLayer: CAShapeLayer = {
		let scale: CGFloat = 0.4
		let size = min(bounds.size.width, bounds.size.height) * scale
		let originalSize = size / scale
		let margin = ((1 - scale) / 2) * originalSize

		let checkmarkPath = with(NSBezierPath()) {
			$0.move(to: CGPoint(x: 0, y: size / 2))
			$0.line(to: CGPoint(x: size / 3, y: size / 6))
			$0.line(to: CGPoint(x: size, y: 5 * size / 6))
		}

		return with(CAShapeLayer()) {
			$0.frame = CGRect(x: margin, y: margin, width: size, height: size)
			$0.path = checkmarkPath.cgPath
			$0.fillColor = nil
			$0.fillMode = .forwards
			$0.lineCap = .round
			$0.lineJoin = .miter
			$0.lineWidth = lineWidth
			$0.strokeColor = color.cgColor
		}
	}()

	// MARK: - CheckmarkView (Animation)

	private lazy var animation = with(CAKeyframeAnimation(keyPath: #keyPath(CAShapeLayer.strokeEnd))) {
		$0.values = [0, 1.0]
		$0.duration = animationDuration
		$0.timingFunctions = [
			CAMediaTimingFunction(name: .easeOut)
		]
	}

	private let animationKey = "checkmarkAnimation"

	private func startAnimation() {
		if shapeLayer.animation(forKey: animationKey) == nil {
			shapeLayer.add(animation, forKey: animationKey)
		}
	}

	private func stopAnimation() {
		shapeLayer.removeAnimation(forKey: animationKey)
	}
}
