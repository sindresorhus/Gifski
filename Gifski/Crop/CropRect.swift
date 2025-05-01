//
//  CropRect.swift
//  Gifski
//
//  Created by Michael Mulet on 4/27/25.
//

import Foundation
import CoreGraphics
import SwiftUI

/**
 Represents a crop rect. Both size and origin are unit points, so it does not matter what the aspect of the source  is
 */
struct CropRect: Equatable {
	var origin: UnitPoint
	var size: UnitPoint

	init(origin: UnitPoint, size: UnitPoint) {
		self.origin = origin
		self.size = size
	}
	init(x: Double, y: Double, width: Double, height: Double) {
		self.origin = .init(x: x, y: y)
		self.size = .init(x: width, y: height)
	}


	var width: Double {
		get {
			size.x
		}
		set {
			size.x = newValue
		}
	}
	var height: Double {
		get {
			size.y
		}
		set {
			size.y = newValue
		}
	}
	var x: Double {
		get {
			origin.x
		}
		set {
			origin.x = newValue
		}
	}
	var y: Double {
		get {
			origin.y
		}
		set {
			origin.y = newValue
		}
	}
	var midX: Double {
		origin.x + (size.x / 2)
	}
	var midY: Double {
		origin.y + (size.y / 2)
	}


	static let initialCropRect: CropRect = .init(x: 0, y: 0, width: 1, height: 1)
	var isReset: Bool {
		origin.x == 0 && origin.y == 0 && size.x == 1 && size.y == 1
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
	 The mininum cropRect width/height in pixels. As crop rects use unitPoints for size, you need frame to convert a crop rect to pixels and use [CropRect.minSize](CropRect.minSize)
	 */
	static let minRectWidthHeight = 40.0

	static func minSize(frame: CGRect) -> UnitPoint {
		.init(x: minRectWidthHeight / frame.width, y: minRectWidthHeight / frame.height)
	}


	func applyDragToCropRect(
		drag: DragGesture.Value,
		frame: CGRect,
		position: CropHandlePosition,
		dragMode: DragMode
	) -> CropRect {
		let delta = getRelativeDragDelta(drag: drag, position: position, frame: frame)

		if position == .center {
			return applyCenterDrag(delta: delta)
		}
		let minSize = CropRect.minSize(frame: frame)
		switch dragMode {
		case .normal:
			return applyNormal(
				position: position,
				minSize: minSize,
				delta: delta
			)
		case .symmetric:
			return applySymmetric(
				position: position,
				minSize: minSize,
				delta: delta
			)
		case .scale:
			return applyScale(
				position: position,
				minSize: minSize,
				delta: delta
			)
		case .aspectRatioLockScale:
			return applyAspectRatioLock(
				minSize: minSize,
				dragLocation: drag.locationInside(frame: frame)
			)
		}
	}

	func getRelativeDragDelta(drag: DragGesture.Value, position: CropHandlePosition, frame: CGRect) -> UnitPoint{
		let (locationX, locationY) = position.location
		let dragStartAnchor: UnitPoint = {
			switch position {
			case .bottom, .right, .center, .left, .top:
				return .init(x: drag.startLocation.x / frame.width, y: drag.startLocation.y / frame.height)
			case .topLeft, .topRight, .bottomLeft, .bottomRight:
				return .init(
					x: x + width * locationX,
					y: y + height * locationY
				)
			}
		}()
		let dragLocation = drag.locationInside(frame: frame)
		return .init(x: dragLocation.x - dragStartAnchor.x, y: dragLocation.y - dragStartAnchor.y)
	}

	/**
	 Drag the crop rect without scaling. Also prevents the crop rect from leaving the rect,
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
	 Apply normal dragging, if you grab the top left corner the bottom location and right hand side location remain the same while the top and left sides move. Also prevents the crop rect from leaving the rect, and it has minium size.
	 */
	func applyNormal(
		position: CropHandlePosition,
		minSize: UnitPoint,
		delta: UnitPoint
	) -> CropRect {
		let (dx, dWidth) = Self.helpNormal(
			primary: position.isLeft,
			secondary: position.isRight,
			origin: x,
			size: width,
			minSize: minSize.width,
			raw: delta.x
		)

		let (dy, dHeight) = Self.helpNormal(
			primary: position.isTop,
			secondary: position.isBottom,
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
		primary: Bool,
		secondary: Bool,
		origin: Double,
		size: Double,
		minSize: Double,
		raw: Double
	) -> (Double, Double) {
		if primary {
			let dx = raw.clamped(from: -origin, to: size - minSize)
			return (dx, -dx)
		}
		guard secondary else {
			return (0.0, 0.0)
		}
		return (0.0, raw.clamped(from: minSize - size, to: (1.0 - origin) - size))
	}

	/**
	 Apply a scaling such that it is symmetric depending on drag direction (if you drag a corner along the axis to the center the entire rect will scale uniformly from the center. If you drag to the left the entire crop rect will scale horizontially from the the center, and so on).  Also prevents the crop rect from leaving the rect, and it has minium size.
	 */
	func applySymmetric(
		position: CropHandlePosition,
		minSize: UnitPoint,
		delta: UnitPoint
	) -> CropRect {
		let dx = Double(delta.x).clamped(to: Self.symmetricDeltaRange(
			primary: position.isLeft,
			secondary: position.isRight,
			origin: x,
			size: width,
			minSize: minSize.width
		))
		let dy = Double(delta.y).clamped(to: Self.symmetricDeltaRange(
			primary: position.isTop,
			secondary: position.isBottom,
			origin: y,
			size: height,
			minSize: minSize.height
		))
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
	 for applySymmetric. primary is left/top, secondary is right/bottom.
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
	Scale the crop rect by finding an anchor point on the opposite side of the handle (so if you grab the top left, the anchor point would be on the bottom right), then apply scale. Also prevents the crop rect from leaving the rect, and it has a minium size.
	*/
	func applyScale(
		position: CropHandlePosition,
		minSize: UnitPoint,
		delta: UnitPoint
	) -> CropRect {
		let (locationX, locationY) = position.location
		let scaleX = (locationX * 2) - 1
		let scaleY = (locationY * 2) - 1

		let handleCount = max((abs(scaleX) > 0 ? 1 : 0) + (abs(scaleY) > 0 ? 1 : 0), 1)
		let (tempScale, anchorX) = Self.scaleAnchorPoint(
			origin: x,
			size: width,
			location: locationX,
			scale: 1 + (scaleX * delta.x / width + scaleY * delta.y / height) / Double(handleCount)
		)
		var (scale, anchorY) = Self.scaleAnchorPoint(
			origin: y,
			size: height,
			location: locationY,
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
	 for [applyScale](UpdateCropRect.applyScale)
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
	 scale the crop rect while maintaining aspect ratio.  Also prevents the crop rect from leaving the rect, and it has minium size.
	 */
	func applyAspectRatioLock(
		minSize: UnitPoint,
		dragLocation: UnitPoint
	) -> CropRect {
		let dx = abs(dragLocation.x - midX)
		let dy = abs(dragLocation.y - midY)

		let rawScale = max(
			dx / (width / 2),
			dy / (height / 2)
		)

		let minScale = max(
			minSize.width / width,
			minSize.height / height
		)

		let maxScale = [
			2 * midX / width,
			2 * (1 - midX) / width,
			2 * midY / height,
			2 * (1 - midY) / height
		].min() ?? 1

		let scale = (minScale < maxScale)
		? rawScale.clamped(from: minScale, to: maxScale)
		: 1.0

		let width = width * scale
		let height = height * scale
		return CropRect(
			x: midX - width / 2,
			y: midY - height / 2,
			width: width,
			height: height
		)
	}
}
extension UnitPoint {
	var width: Double {
		x
	}
	var height: Double {
		y
	}
}

extension DragGesture.Value {
	/**
	 You can drag outside of the view's frame, this will clamp it back to an edge
	 */
	func locationInside(frame: CGRect) -> UnitPoint {
		.init(
			x: location.x.clamped(from: frame.minX, to: frame.maxX) / frame.width,
			y: location.y.clamped(from: frame.minY, to: frame.maxY) / frame.height
		)
	}
}
