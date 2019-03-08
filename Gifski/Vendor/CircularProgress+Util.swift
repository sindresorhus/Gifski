import AppKit

extension NSBezierPath {
	static func circle(radius: Double, center: CGPoint, startAngle: Double = 0, endAngle: Double = 360) -> NSBezierPath {
		let path = NSBezierPath()
		path.appendArc(
			withCenter: center,
			radius: CGFloat(radius),
			startAngle: CGFloat(startAngle),
			endAngle: CGFloat(endAngle)
		)
		return path
	}
}

extension CALayer {
	/// This is required for CALayers that are created independently of a view
	func setAutomaticContentsScale() {
		contentsScale = NSScreen.main?.backingScaleFactor ?? 2
	}

	/**
	Set CALayer properties without the implicit animation

	```
	CALayer.withoutImplicitAnimations {
		view.layer?.opacity = 0.4
	}
	```
	*/
	static func withoutImplicitAnimations(closure: () -> Void) {
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		closure()
		CATransaction.commit()
	}

	/**
	Toggle the implicit CALayer animation
	Can be useful for text layers
	*/
	var implicitAnimations: Bool {
		get {
			return actions == nil
		}
		set {
			if newValue {
				actions = nil
			} else {
				actions = ["contents": NSNull()]
			}
		}
	}

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
			CATransaction.setAnimationTimingFunction(timingFunction)

			if let completion = completion {
				CATransaction.setCompletionBlock(completion)
			}

			animations()
			CATransaction.commit()
		}
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

/**
Shows the indeterminate state, when it's activated.

It draws part of a circle that gets animated into a looping motion around its core.
*/
final class IndeterminateShapeLayer: CAShapeLayer {
	convenience init(radius: Double, center: CGPoint) {
		self.init()
		fillColor = nil
		path = NSBezierPath.circle(radius: radius, center: bounds.center, startAngle: 270).cgPath
		anchorPoint = CGPoint(x: 0.5, y: 0.5)
		position = center
	}
}

extension CABasicAnimation {
	/// Rotates the element around its center point infinitely.
	static var rotate: CABasicAnimation {
		let animation = CABasicAnimation(keyPath: #keyPath(CAShapeLayer.transform))
		animation.valueFunction = CAValueFunction(name: .rotateZ)
		animation.fromValue = 0
		animation.toValue = -(Double.pi * 2)
		animation.duration = 1
		animation.repeatCount = .infinity
		animation.timingFunction = CAMediaTimingFunction(name: .linear)

		return animation
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

extension NSFont {
	static let helveticaNeueLight = NSFont(name: "HelveticaNeue-Light", size: 0)
}

extension NSColor {
	typealias HSBAColor = (hue: Double, saturation: Double, brightness: Double, alpha: Double)
	var hsba: HSBAColor {
		var hue: CGFloat = 0
		var saturation: CGFloat = 0
		var brightness: CGFloat = 0
		var alpha: CGFloat = 0
		let color = usingColorSpace(.deviceRGB) ?? self
		color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
		return HSBAColor(Double(hue), Double(saturation), Double(brightness), Double(alpha))
	}

	/// Adjust color components by ratio.
	func adjusting(
		hue: Double = 0,
		saturation: Double = 0,
		brightness: Double = 0,
		alpha: Double = 0
	) -> NSColor {
		let color = hsba
		return NSColor(
			hue: CGFloat(color.hue * (hue + 1)),
			saturation: CGFloat(color.saturation * (saturation + 1)),
			brightness: CGFloat(color.brightness * (brightness + 1)),
			alpha: CGFloat(color.alpha * (alpha + 1))
		)
	}
}
