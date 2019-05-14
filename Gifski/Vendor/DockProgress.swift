// Vendored from: https://github.com/sindresorhus/DockProgress
// TODO: Use Carthage and frameworks again when targeting macOS 10.14.4 since it's ABI stable
import Cocoa

public final class DockProgress {
	private static let appIcon = NSApp.applicationIconImage!
	private static var previousProgress: Double = 0
	private static var progressObserver: NSKeyValueObservation?
	private static var finishedObserver: NSKeyValueObservation?

	private static var dockImageView = with(NSImageView()) {
		NSApp.dockTile.contentView = $0
	}

	public static var progressInstance: Progress? {
		didSet {
			if let progressInstance = progressInstance {
				progressObserver = progressInstance.observe(\.fractionCompleted) { sender, _ in
					guard !sender.isCancelled && !sender.isFinished else {
						return
					}

					progress = sender.fractionCompleted
				}

				finishedObserver = progressInstance.observe(\.isFinished) { sender, _ in
					guard !sender.isCancelled && sender.isFinished else {
						return
					}

					progress = 1
				}
			}
		}
	}

	public static var progress: Double = 0 {
		didSet {
			if previousProgress == 0 || (progress - previousProgress).magnitude > 0.01 {
				previousProgress = progress
				updateDockIcon()
			}
		}
	}

	/// Reset the `progress` without animating
	public static func resetProgress() {
		progress = 0
		previousProgress = 0
		updateDockIcon()
	}

	public enum ProgressStyle {
		case bar
		// TODO: Make `color` optional when https://github.com/apple/swift-evolution/blob/master/proposals/0155-normalize-enum-case-representation.md is shipping in Swift
		case circle(radius: Double, color: NSColor)
		case badge(color: NSColor, badgeValue: () -> Int)
		case custom(drawHandler: (_ rect: CGRect) -> Void)
	}

	public static var style: ProgressStyle = .bar

	// TODO: Make the progress smoother by also animating the steps between each call to `updateDockIcon()`
	private static func updateDockIcon() {
		// TODO: If the `progress` is 1, draw the full circle, then schedule another draw in n milliseconds to hide it
		let icon = (0..<1).contains(progress) ? draw() : appIcon
		DispatchQueue.main.async {
			// TODO: Make this better by drawing in the `contentView` directly instead of using an image
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
			case let .badge(color, badgeValue):
				self.drawProgressBadge(dstRect, color: color, badgeLabel: badgeValue())
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
		barProgress.size.width = barProgress.width * CGFloat(progress)
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
		progressCircle.progress = progress
		progressCircle.render(in: cgContext)
	}

	private static func drawProgressBadge(_ dstRect: CGRect, color: NSColor, badgeLabel: Int) {
		guard let cgContext = NSGraphicsContext.current?.cgContext else {
			return
		}

		let radius = dstRect.width / 4.8
		let newCenter = CGPoint(x: dstRect.maxX - radius - 4, y: dstRect.minY + radius + 4)

		// Background
		let badge = ProgressCircleShapeLayer(radius: Double(radius), center: newCenter)
		badge.fillColor = CGColor(red: 0.94, green: 0.96, blue: 1, alpha: 1)
		badge.shadowColor = .black
		badge.shadowOpacity = 0.3
		badge.masksToBounds = false
		badge.shadowOffset = CGSize(width: -1, height: 1)
		badge.shadowPath = badge.path

		// Progress circle
		let lineWidth: CGFloat = 6
		let innerRadius = radius - lineWidth / 2
		let progressCircle = ProgressCircleShapeLayer(radius: Double(innerRadius), center: newCenter)
		progressCircle.strokeColor = color.cgColor
		progressCircle.lineWidth = lineWidth
		progressCircle.lineCap = .butt
		progressCircle.progress = progress

		// Label
		let dimension = badge.bounds.height - 5
		let rect = CGRect(origin: progressCircle.bounds.origin, size: CGSize(width: dimension, height: dimension))
		let textLayer = VerticallyCenteredTextLayer(frame: rect, center: newCenter)
		let badgeText = kiloShortStringFromInt(number: badgeLabel)
		textLayer.foregroundColor = CGColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1)
		textLayer.string = badgeText
		textLayer.fontSize = scaledBadgeFontSize(text: badgeText)
		textLayer.font = NSFont.helveticaNeueBold
		textLayer.alignmentMode = .center
		textLayer.truncationMode = .end

		badge.addSublayer(textLayer)
		badge.addSublayer(progressCircle)
		badge.render(in: cgContext)
	}

	/**
	```
	999 => 999
	1000 => 1K
	1100 => 1K
	2000 => 2K
	10000 => 9K+
	```
	*/
	private static func kiloShortStringFromInt(number: Int) -> String {
		let sign = number.signum()
		let absNumber = abs(number)

		if absNumber < 1000 {
			return "\(number)"
		} else if absNumber < 10_000 {
			return "\(sign * Int(absNumber / 1000))k"
		} else {
			return "\(sign * 9)k+"
		}
	}

	private static func scaledBadgeFontSize(text: String) -> CGFloat {
		switch text.count {
		case 1:
			return 30
		case 2:
			return 23
		case 3:
			return 19
		case 4:
			return 15
		default:
			return 0
		}
	}
}




///
/// util.swift
///

extension NSBezierPath {
	/// For making a circle progress indicator
	static func progressCircle(radius: Double, center: CGPoint) -> Self {
		let startAngle: CGFloat = 90
		let path = self.init()
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


extension NSFont {
	static let helveticaNeueBold = NSFont(name: "HelveticaNeue-Bold", size: 0)
}


extension NSBezierPath {
	/// UIKit polyfill
	var cgPath: CGPath {
		let path = CGMutablePath()
		var points = [CGPoint](repeating: .zero, count: 3)

		for index in 0..<elementCount {
			let type = element(at: index, associatedPoints: &points)
			switch type {
			case .moveTo:
				path.move(to: points[0])
			case .lineTo:
				path.addLine(to: points[0])
			case .curveTo:
				path.addCurve(to: points[2], control1: points[0], control2: points[1])
			case .closePath:
				path.closeSubpath()
			@unknown default:
				assertionFailure("NSBezierPath received a new enum case. Please handle it.")
			}
		}

		return path
	}

	/// UIKit polyfill
	convenience init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
		self.init(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
	}
}


/// Fixes the vertical alignment issue of the `CATextLayer` class.
final class VerticallyCenteredTextLayer: CATextLayer {
	convenience init(frame rect: CGRect, center: CGPoint) {
		self.init()
		frame = rect
		frame.center = center
		contentsScale = NSScreen.main?.backingScaleFactor ?? 2
	}

	// From https://stackoverflow.com/a/44055040/6863743
	override func draw(in context: CGContext) {
		let height = bounds.size.height
		let deltaY = ((height - fontSize) / 2 - fontSize / 10) * -1

		context.saveGState()
		context.translateBy(x: 0, y: deltaY)
		super.draw(in: context)
		context.restoreGState()
	}
}
