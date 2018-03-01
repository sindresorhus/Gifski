import Cocoa


/**
Convenience function for initializing an object and modifying its properties

```
let label = with(NSTextField()) {
	$0.stringValue = "Foo"
	$0.textColor = .systemBlue
	view.addSubview($0)
}
```
*/
@discardableResult
func with<T>(_ item: T, update: (inout T) throws -> Void) rethrows -> T {
	var this = item
	try update(&this)
	return this
}


extension NSBezierPath {
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


extension NSColor {
	func with(alpha: Double) -> NSColor {
		return withAlphaComponent(CGFloat(alpha))
	}
}


extension CGRect {
	var center: CGPoint {
		get {
			return CGPoint(x: midX, y: midY)
		}
		set {
			origin = CGPoint(
				x: newValue.x - (size.width / 2),
				y: newValue.y - (size.height / 2)
			)
		}
	}
}


extension NSBezierPath {
	/// UIKit polyfill
	var cgPath: CGPath {
		let path = CGMutablePath()
		var points = [CGPoint](repeating: .zero, count: 3)

		for i in 0..<elementCount {
			let type = element(at: i, associatedPoints: &points)
			switch type {
			case .moveToBezierPathElement:
				path.move(to: points[0])
			case .lineToBezierPathElement:
				path.addLine(to: points[0])
			case .curveToBezierPathElement:
				path.addCurve(to: points[2], control1: points[0], control2: points[1])
			case .closePathBezierPathElement:
				path.closeSubpath()
			}
		}

		return path
	}

	/// UIKit polyfill
	convenience init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
		self.init(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
	}
}
