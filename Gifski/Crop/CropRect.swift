import SwiftUI

/**
Represents a crop rect.

Both size and origin are unit points, so it does not matter what the aspect of the source is.
*/
struct CropRect: Equatable {
	var origin: UnitPoint
	var size: UnitSize
}

extension CropRect {
	static let initialCropRect = Self(x: 0, y: 0, width: 1, height: 1)

	init(
		x: Double,
		y: Double,
		width: Double,
		height: Double
	) {
		self.origin = .init(x: x, y: y)
		self.size = .init(width: width, height: height)
	}

	var width: Double {
		size.width
	}

	var height: Double {
		size.height
	}

	var x: Double {
		origin.x
	}

	var y: Double {
		origin.y
	}

	var midX: Double {
		origin.x + (size.width / 2)
	}

	var midY: Double {
		origin.y + (size.height / 2)
	}

	enum Axis {
		case horizontal
		case vertical

		// swiftlint:disable:next no_cgfloat
		var origin: WritableKeyPath<UnitPoint, CGFloat> {
			switch self {
			case .horizontal:
				\.x
			case .vertical:
				\.y
			}
		}

		var size: WritableKeyPath<UnitSize, Double> {
			switch self {
			case .horizontal:
				\.width
			case .vertical:
				\.height
			}
		}
	}

	func mid(axis: Axis) -> Double {
		switch axis {
		case .horizontal:
			midX
		case .vertical:
			midY
		}
	}

	var isReset: Bool {
		origin.x == 0 && origin.y == 0 && size.width == 1 && size.height == 1
	}

	/**
	Produce an unnormalized `CGRect` in pixels.
	*/
	func unnormalize(forDimensions dimensions: CGSize) -> CGRect {
		.init(
			x: dimensions.width * x,
			y: dimensions.height * y,
			width: dimensions.width * width,
			height: dimensions.height * height
		)
	}

	func unnormalize(forDimensions dimensions: (Int, Int)) -> CGRect {
		unnormalize(forDimensions: .init(width: Double(dimensions.0), height: Double(dimensions.1)))
	}

	/**
	Creates a new `CropRect` with a given aspect ratio.

	If the crop rect is full screen, it potentially expands the crop (lengthening the longest side of the rect), otherwise it will keep the crop inside the current crop rect (trying to keep the longest side of the rect the same, unless it would exceed the video dimensions).
	*/
	func withAspectRatio(
		aspectWidth: Double,
		aspectHeight: Double,
		forDimensions dimensions: CGSize
	) -> Self {
		if width == 1.0 || height == 1.0 {
			return Self.centeredFrom(
				aspectWidth: aspectWidth,
				aspectHeight: aspectHeight,
				forDimensions: dimensions
			)
		}

		return withAspectRatioInsideCurrentRect(
			aspectWidth: aspectWidth,
			aspectHeight: aspectHeight,
			withinVideoDimensions: dimensions
		)
	}

	/**
	The range of valid numbers for the aspect ratio.
	*/
	static let defaultAspectRatioBounds = 1...99

	/**
	Adjusts the crop rect to fit a specified aspect ratio inside the current rect and scaling down if necessary to ensure it remains within the given video dimensions.

	- Parameters:
	 - aspectWidth: The width of the desired aspect ratio.
	 - aspectHeight: The height of the desired aspect ratio.
	 - dimensions: The dimensions of the video in pixels.

	- Returns: A new `CropRect` adjusted to the specified aspect ratio and constrained within the video dimensions.
	*/
	private func withAspectRatioInsideCurrentRect(
		aspectWidth: Double,
		aspectHeight: Double,
		withinVideoDimensions dimensions: CGSize
	) -> Self {
		let cropRectInPixels = unnormalize(forDimensions: dimensions)
		let aspectSize = CGSize(width: aspectWidth, height: aspectHeight)

		let newLongestSide = withAspectRatioInsideCurrentRectLongestSide(
			cropRectInPixels: cropRectInPixels,
			aspectSize: aspectSize,
			withinVideoDimensions: dimensions
		)

		let newAspect = Self.clampAspect(
			aspectRatio: aspectSize.aspectRatio,
			newLongestSide: newLongestSide
		)

		return cropRectInPixels
			.centeredRectWith(size: newAspect * newLongestSide)
			.toCropRect(forVideoDimensions: dimensions)
	}

	private func withAspectRatioInsideCurrentRectLongestSide(
		cropRectInPixels: CGRect,
		aspectSize: CGSize,
		withinVideoDimensions dimensions: CGSize
	) -> Double {
		let normalizedAspect = aspectSize.aspectRatio.normalizedAspectRatioSides

		let scaleBounds = Self.scaleBounds(
			videoDimensions: dimensions,
			center: cropRectInPixels.center,
			normalizedAspect: normalizedAspect
		)

		let desiredScale = aspectSize
			.aspectFittedSize(targetWidthHeight: cropRectInPixels.size.longestSide)[keyPath: Self.desiredSide(aspectRatio: normalizedAspect.aspectRatio)]
			.toDouble

		return desiredScale.clamped(to: scaleBounds)
	}

	/**
	Adjusts the aspect ratio such that it is achievable (not too small).
	*/
	private static func clampAspect(aspectRatio: Double, newLongestSide: Double) -> CGSize {
		if aspectRatio >= 1.0 {
			return min(aspectRatio, newLongestSide / minRectWidthHeight).normalizedAspectRatioSides
		}
		return max(aspectRatio, minRectWidthHeight / newLongestSide).normalizedAspectRatioSides
	}

	// swiftlint:disable:next no_cgfloat
	private static func desiredSide(aspectRatio: Double) -> KeyPath<CGSize, CGFloat> {
		aspectRatio >= 1.0 ? \.width : \.height
	}

	private static func scaleBounds(
		videoDimensions dimensions: CGSize,
		center: CGPoint,
		normalizedAspect: CGSize
	) -> ClosedRange<Double> {
		let maxScale = min(
			maxScaleForSide(
				in: 0...dimensions.width,
				center: center.x,
				normalizedAspectOfSide: normalizedAspect.width
			),
			maxScaleForSide(
				in: 0...dimensions.height,
				center: center.y,
				normalizedAspectOfSide: normalizedAspect.height
			)
		)

		return 0...maxScale
	}

	private static func maxScaleForSide(
		in range: ClosedRange<Double>,
		center: Double,
		normalizedAspectOfSide: Double = 1.0
	) -> Double {
		min(center - range.lowerBound, range.upperBound - center) * 2.0 / normalizedAspectOfSide
	}

	/**
	Returns a new `CGRect` trying to expand or shrink the size. If the size is within the video bounds it will expand, otherwise it will change the center position and expand)
	*/
	func changeSize(size: UnitSize, minSize: UnitSize) -> Self {
		var out = Self(x: 0.0, y: 0.0, width: 0.0, height: 0.0)
		changeSizeFor(axis: .horizontal, size: size, minSize: minSize, out: &out)
		changeSizeFor(axis: .vertical, size: size, minSize: minSize, out: &out)
		return out
	}

	private func changeSizeFor(
		axis: Axis,
		size: UnitSize,
		minSize: UnitSize,
		out: inout Self
	) {
		let newSideLength = size[keyPath: axis.size].clamped(
			from: minSize[keyPath: axis.size],
			to: 1.0
		)

		var newOrigin = mid(axis: axis) - newSideLength / 2.0

		if newOrigin < 0 {
			newOrigin = 0
		} else if newOrigin + newSideLength > 1.0 {
			newOrigin = 1.0 - newSideLength
		}

		out.origin[keyPath: axis.origin] = newOrigin
		out.size[keyPath: axis.size] = newSideLength
	}
}

extension CropRect {
	enum DragMode {
		case normal
		case symmetric
		case scale
		case aspectRatioLockScale
	}

	/**
	The minimum crop rect width/height in pixels.

	As crop rectangles use unit points for size, you need a frame to convert a crop rect to pixels and use `CropRect.minSize`.
	*/
	static let minRectWidthHeight = 100.0

	static func minSize(videoSize: CGSize) -> UnitSize {
		.init(width: minRectWidthHeight / videoSize.width, height: minRectWidthHeight / videoSize.height)
	}

	/**
	Returns a crop rect centered in a video from an aspect and dimensions.
	*/
	static func centeredFrom(
		aspectWidth: Double,
		aspectHeight: Double,
		forDimensions dimensions: CGSize
	) -> CropRect {
		let aspectSize = CGSize(width: aspectWidth, height: aspectHeight)

		let fittedSize = aspectSize.aspectFittedSize(
			targetWidth: dimensions.width,
			targetHeight: dimensions.height
		)

		let newAspect = clampAspect(
			aspectRatio: aspectSize.aspectRatio,
			newLongestSide: fittedSize.longestSide
		)

		let newSize = newAspect * fittedSize.longestSide
		let cropWidth = newSize.width / dimensions.width
		let cropHeight = newSize.height / dimensions.height

		return .init(
			origin: .init(
				x: 0.5 - cropWidth / 2.0,
				y: 0.5 - cropHeight / 2.0
			),
			size: .init(
				width: cropWidth,
				height: cropHeight
			)
		)
	}

	func applyDragToCropRect(
		drag: DragGesture.Value,
		frame: CGRect,
		dimensions: CGSize,
		position: CropHandlePosition,
		dragMode: DragMode
	) -> CropRect {
		let delta = getRelativeDragDelta(drag: drag, position: position, frame: frame)

		if position == .center {
			return applyCenterDrag(delta: delta)
		}

		let minSize = CropRect.minSize(videoSize: dimensions)

		return switch dragMode {
		case .normal:
			applyNormal(
				position: position,
				minSize: minSize,
				delta: delta
			)
		case .symmetric:
			applySymmetric(
				position: position,
				minSize: minSize,
				delta: delta
			)
		case .scale:
			applyScale(
				position: position,
				minSize: minSize,
				delta: delta
			)
		case .aspectRatioLockScale:
			applyAspectRatioLock(
				minSize: minSize,
				dragLocation: drag.locationInside(frame: frame)
			)
		}
	}

	func getRelativeDragDelta(
		drag: DragGesture.Value,
		position: CropHandlePosition,
		frame: CGRect
	) -> UnitPoint {
		let dragStartAnchor: UnitPoint = switch position {
		case .bottom, .right, .center, .left, .top:
			.init(x: drag.startLocation.x / frame.width, y: drag.startLocation.y / frame.height)
		case .topLeft, .topRight, .bottomLeft, .bottomRight:
			.init(
				x: x + width * position.location.x,
				y: y + height * position.location.y
			)
		}

		let dragLocation = drag.locationInside(frame: frame)

		return .init(x: dragLocation.x - dragStartAnchor.x, y: dragLocation.y - dragStartAnchor.y)
	}

	/**
	Drag the crop rect without scaling.

	Also prevents the crop rect from leaving the rect.
	*/
	func applyCenterDrag(
		delta: UnitPoint
	) -> CropRect {
		.init(
			x: x + delta.x.clamped(from: -x, to: 1.0 - x - width),
			y: y + delta.y.clamped(from: -y, to: 1.0 - y - height),
			width: width,
			height: height
		)
	}

	/**
	Apply normal dragging.

	If you grab the top-left corner, the bottom location and right-hand side location remains the same while the top and left sides move.

	Also prevents the crop rect from leaving the rect, and it has a minimum size.
	*/
	func applyNormal(
		position: CropHandlePosition,
		minSize: UnitSize,
		delta: UnitPoint
	) -> CropRect {
		let (dx, dWidth) = Self.helpNormal(
			isPrimary: position.isLeft,
			isSecondary: position.isRight,
			origin: x,
			size: width,
			minSize: minSize.width,
			raw: delta.x
		)

		let (dy, dHeight) = Self.helpNormal(
			isPrimary: position.isTop,
			isSecondary: position.isBottom,
			origin: y,
			size: height,
			minSize: minSize.height,
			raw: delta.y
		)

		return .init(
			x: x + dx,
			y: y + dy,
			width: width + dWidth,
			height: height + dHeight
		)
	}

	private static func helpNormal(
		isPrimary: Bool,
		isSecondary: Bool,
		origin: Double,
		size: Double,
		minSize: Double,
		raw: Double
	) -> (Double, Double) {
		switch (isPrimary, isSecondary) {
		case (true, _):
			let dx = raw.clamped(from: -origin, to: size - minSize)
			return (dx, -dx)
		case (_, true):
			return (0.0, raw.clamped(from: minSize - size, to: (1.0 - origin) - size))
		default:
			return (0.0, 0.0)
		}
	}

	/**
	Apply a scaling such that it is symmetric depending on drag direction.

	For example, if you drag a corner along the axis to the center, the entire rect will scale uniformly from the center. If you drag to the left, the entire crop rect will scale horizontally from the center, and so on.

	Also prevents the crop rect from leaving the rect, and it has minimum size.
	*/
	func applySymmetric(
		position: CropHandlePosition,
		minSize: UnitSize,
		delta: UnitPoint
	) -> CropRect {
		let dx = Double(delta.x).clamped(
			to: Self.symmetricDeltaRange(
				primary: position.isLeft,
				secondary: position.isRight,
				origin: x,
				size: width,
				minSize: minSize.width
			)
		)

		let dy = Double(delta.y).clamped(
			to: Self.symmetricDeltaRange(
				primary: position.isTop,
				secondary: position.isBottom,
				origin: y,
				size: height,
				minSize: minSize.height
			)
		)

		let xSign = position.isLeft ? 1.0 : position.isRight ? -1.0 : 0.0
		let ySign = position.isTop ? 1.0 : position.isBottom ? -1.0 : 0.0

		return .init(
			x: x + xSign * dx,
			y: y + ySign * dy,
			width: width - 2 * xSign * dx,
			height: height - 2 * ySign * dy
		)
	}

	/**
	For `applySymmetric`.

	- `primary` is left/top.
	- `secondary` is right/bottom.
	*/
	static func symmetricDeltaRange(
		primary: Bool,
		secondary: Bool,
		origin: Double,
		size: Double,
		minSize: Double
	) -> ClosedRange<Double> {
		if primary {
			let lower = max(-origin, origin + size - 1)
			let upper = (size - minSize) / 2
			return lower...upper
		}

		guard secondary else {
			return 0...0
		}

		let lower = (minSize - size) / 2
		let upper = min(origin, 1 - (origin + size))

		return lower...upper
	}

	/**
	Scale the crop rect by finding an anchor point on the opposite side of the handle (so if you grab the top left, the anchor point would be on the bottom-right), then apply scale.

	Also prevents the crop rect from leaving the rect, and it has a minimum size.
	*/
	func applyScale(
		position: CropHandlePosition,
		minSize: UnitSize,
		delta: UnitPoint
	) -> CropRect {
		let scaleX = (position.location.x * 2) - 1
		let scaleY = (position.location.y * 2) - 1

		let handleCount = max((abs(scaleX) > 0 ? 1 : 0) + (abs(scaleY) > 0 ? 1 : 0), 1)

		let (tempScale, anchorX) = Self.scaleAnchorPoint(
			origin: x,
			size: width,
			location: position.location.x,
			scale: 1 + (scaleX * delta.x / width + scaleY * delta.y / height) / Double(handleCount)
		)

		var (scale, anchorY) = Self.scaleAnchorPoint(
			origin: y,
			size: height,
			location: position.location.y,
			scale: tempScale
		)

		scale = max(scale, minSize.width / width, minSize.height / height)

		return .init(
			x: anchorX - (anchorX - x) * scale,
			y: anchorY - (anchorY - y) * scale,
			width: width * scale,
			height: height * scale
		)
	}

	/**
	For  `applyScale`.
	*/
	static func scaleAnchorPoint(
		origin: Double,
		size: Double,
		location: Double,
		scale inScale: Double
	) -> (scale: Double, anchor: Double) {
		let anchor = origin + size * (1 - location)
		var scale = inScale

		if anchor > 0 {
			scale = min(anchor / (anchor - origin), scale)
		}

		if anchor < 1 {
			scale = min((1 - anchor) / (origin + size - anchor), scale)
		}

		return (scale: scale, anchor: anchor)
	}

	/**
	Scale the crop rect while maintaining aspect ratio.

	Also prevents the crop rect from leaving the rect, and it has minimum size.
	*/
	func applyAspectRatioLock(
		minSize: UnitSize,
		dragLocation: UnitPoint
	) -> CropRect {
		let dx = abs(dragLocation.x - midX)
		let dy = abs(dragLocation.y - midY)

		let rawScale = max(
			dx / (width / 2),
			dy / (height / 2)
		)

		let scaleRange = max(
			minSize.width / width,
			minSize.height / height
		)...[
			2 * midX / width,
			2 * (1 - midX) / width,
			2 * midY / height,
			2 * (1 - midY) / height
		].min()!

		let scale = rawScale.clamped(to: scaleRange)

		let newWidth = width * scale
		let newHeight = height * scale

		return CropRect(
			x: midX - newWidth / 2,
			y: midY - newHeight / 2,
			width: newWidth,
			height: newHeight
		)
	}
}

/**
A normalized 2D size in a view’s coordinate space.

`UnitSize` is for sizes as `UnitPoint` is for points.
*/
struct UnitSize: Hashable {
	var width: Double
	var height: Double
}

extension DragGesture.Value {
	/**
	If you drag outside of the view's frame, this will clamp it back to an edge.
	*/
	func locationInside(frame: CGRect) -> UnitPoint {
		.init(
			x: location.x.clamped(from: frame.minX, to: frame.maxX) / frame.width,
			y: location.y.clamped(from: frame.minY, to: frame.maxY) / frame.height
		)
	}
}
