// Vendored from: https://github.com/sindresorhus/DockProgress
/// TODO: Use Carthage and frameworks again when targeting Swift 5 as it should be ABI stable
import Cocoa

public final class DockProgress {
	private static let appIcon = NSApp.applicationIconImage!
	private static var previousProgressValue: Double = 0
	private static var progressObserver: NSKeyValueObservation?

	private static var dockImageView = with(NSImageView()) {
		NSApp.dockTile.contentView = $0
	}

	public static var progress: Progress? {
		didSet {
			if let progress = progress {
				progressObserver = progress.observe(\.fractionCompleted) { object, _ in
					print("progress", object.fractionCompleted, object.isFinished, object.completedUnitCount, object.totalUnitCount)
					progressValue = object.fractionCompleted
				}
			}
		}
	}

	public static var progressValue: Double = 0 {
		didSet {
			if previousProgressValue == 0 || (progressValue - previousProgressValue).magnitude > 0.01 {
				previousProgressValue = progressValue
				updateDockIcon()
			}
		}
	}

	public static func resetProgress() {
		progressValue = 0
		previousProgressValue = 0
		updateDockIcon()
	}

	public enum ProgressStyle {
		case bar
		/// TODO: Make `color` optional when https://github.com/apple/swift-evolution/blob/master/proposals/0155-normalize-enum-case-representation.md is shipping in Swift
		case circle(radius: Double, color: NSColor)
		case custom(drawHandler: (_ rect: CGRect) -> Void)
	}

	public static var style: ProgressStyle = .bar

	/// TODO: Make the progress smoother by also animating the steps between each call to `updateDockIcon()`
	private static func updateDockIcon() {
		/// TODO: If the `progressValue` is 1, draw the full circle, then schedule another draw in n milliseconds to hide it
		let icon = (0..<1).contains(self.progressValue) ? self.draw() : appIcon
		DispatchQueue.main.async {
			/// TODO: Make this better by drawing in the `contentView` directly instead of using an image
			dockImageView.image = icon
			NSApp.dockTile.display()
		}
	}

	private static func draw() -> NSImage {
		return NSImage(size: appIcon.size, flipped: false) { dstRect in
			NSGraphicsContext.current?.imageInterpolation = .high
			self.appIcon.draw(in: dstRect)

			switch self.style {
			case .bar:
				self.drawProgressBar(dstRect)
			case let .circle(radius, color):
				self.drawProgressCircle(dstRect, radius: radius, color: color)
			case let .custom(drawingHandler):
				drawingHandler(dstRect)
			}

			return true
		}
	}

	private static func drawProgressBar(_ dstRect: CGRect) {
		func roundedRect(_ rect: CGRect) {
			NSBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
		}

		let bar = CGRect(x: 0, y: 20, width: dstRect.width, height: 10)
		NSColor.white.with(alpha: 0.8).set()
		roundedRect(bar)

		let barInnerBg = bar.insetBy(dx: 0.5, dy: 0.5)
		NSColor.black.with(alpha: 0.8).set()
		roundedRect(barInnerBg)

		var barProgress = bar.insetBy(dx: 1, dy: 1)
		barProgress.size.width = barProgress.width * CGFloat(progressValue)
		NSColor.white.set()
		roundedRect(barProgress)
	}

	private static func drawProgressCircle(_ dstRect: CGRect, radius: Double, color: NSColor) {
		guard let cgContext = NSGraphicsContext.current?.cgContext else {
			return
		}

		let progressCircle = ProgressCircleShapeLayer(radius: radius, center: dstRect.center)
		progressCircle.strokeColor = color.cgColor
		progressCircle.lineWidth = 4
		progressCircle.cornerRadius = 3
		progressCircle.progress = progressValue
		progressCircle.render(in: cgContext)
	}
}




///
/// util.swift
///

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
//@discardableResult
//private func with<T>(_ item: T, update: (inout T) throws -> Void) rethrows -> T {
//	var this = item
//	try update(&this)
//	return this
//}


//extension NSBezierPath {
//	static func progressCircle(radius: Double, center: CGPoint) -> NSBezierPath {
//		let startAngle: CGFloat = 90
//		let path = NSBezierPath()
//		path.appendArc(
//			withCenter: center,
//			radius: CGFloat(radius),
//			startAngle: startAngle,
//			endAngle: startAngle - 360,
//			clockwise: true
//		)
//		return path
//	}
//}


//final class ProgressCircleShapeLayer: CAShapeLayer {
//	convenience init(radius: Double, center: CGPoint) {
//		self.init()
//		fillColor = nil
//		lineCap = .round
//		path = NSBezierPath.progressCircle(radius: radius, center: center).cgPath
//	}
//
//	var progress: Double {
//		get {
//			return Double(strokeEnd)
//		}
//		set {
//			strokeEnd = CGFloat(newValue)
//		}
//	}
//}


//private extension NSColor {
//	func with(alpha: Double) -> NSColor {
//		return withAlphaComponent(CGFloat(alpha))
//	}
//}


//private extension CGRect {
//	var center: CGPoint {
//		get {
//			return CGPoint(x: midX, y: midY)
//		}
//		set {
//			origin = CGPoint(
//				x: newValue.x - (size.width / 2),
//				y: newValue.y - (size.height / 2)
//			)
//		}
//	}
//}


//private extension NSBezierPath {
//	/// UIKit polyfill
//	var cgPath: CGPath {
//		let path = CGMutablePath()
//		var points = [CGPoint](repeating: .zero, count: 3)
//
//		for i in 0..<elementCount {
//			let type = element(at: i, associatedPoints: &points)
//			switch type {
//			case .moveToBezierPathElement:
//				path.move(to: points[0])
//			case .lineToBezierPathElement:
//				path.addLine(to: points[0])
//			case .curveToBezierPathElement:
//				path.addCurve(to: points[2], control1: points[0], control2: points[1])
//			case .closePathBezierPathElement:
//				path.closeSubpath()
//			}
//		}
//
//		return path
//	}
//
//	/// UIKit polyfill
//	convenience init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
//		self.init(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
//	}
//}
