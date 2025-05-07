//
//  CropHandlePosition.swift
//  Gifski
//
//  Created by Michael Mulet on 4/27/25.
//

import Foundation
import SwiftUI

enum CropHandlePosition: CaseIterable {
	case top
	case topRight
	case right
	case bottomRight
	case bottom
	case bottomLeft
	case left
	case topLeft
	case center

	var location: UnitPoint {
		sides.location
	}
	var isVerticalOnlyHandle: Bool {
		sides.isVerticalOnlyHandle
	}
	var isLeft: Bool {
		sides.isLeft
	}
	var isRight: Bool {
		sides.isRight
	}
	var isTop: Bool {
		sides.isTop
	}
	var isBottom: Bool {
		sides.isBottom
	}

	var isCorner: Bool {
		switch self {
		case .topLeft, .topRight, .bottomLeft, .bottomRight:
			return true
		case .bottom, .top, .left, .right, .center:
			return false
		}
	}

	var sides: RectSides {
		switch self {
		case .top:
			.init(horizontal: .center, vertical: .primary)
		case .topRight:
			.init(horizontal: .secondary, vertical: .primary)
		case .right:
			.init(horizontal: .secondary, vertical: .center)
		case .bottomRight:
			.init(horizontal: .secondary, vertical: .secondary)
		case .bottom:
			.init(horizontal: .center, vertical: .secondary)
		case .bottomLeft:
			.init(horizontal: .primary, vertical: .secondary)
		case .left:
			.init(horizontal: .primary, vertical: .center)
		case .topLeft:
			.init(horizontal: .primary, vertical: .primary)
		case .center:
			.init(horizontal: .center, vertical: .center)
		}
	}

	private var pointerPosition: FrameResizePosition {
		Self.positionToPointer[self] ?? .top
	}
	private static let positionToPointer: [Self: FrameResizePosition] = [
		.top: .top,
		.topRight: .topTrailing,
		.right: .trailing,
		.bottomRight: .bottomTrailing,
		.bottom: .bottom,
		.bottomLeft: .bottomLeading,
		.left: .leading,
		.topLeft: .topLeading,
		.center: .top
	]

	var pointerStyle: PointerStyle {
		if self == .center {
			return .grabIdle
		}
		return .frameResize(position: pointerPosition)
	}
}


struct RectSides: Equatable, Hashable {
	let horizontal: Side
	let vertical: Side

	var isVerticalOnlyHandle: Bool {
		horizontal == .center && vertical != .center
	}

	var isLeft: Bool {
		horizontal == .primary
	}

	var isRight: Bool {
		horizontal == .secondary
	}

	var isTop: Bool {
		vertical == .primary
	}

	var isBottom: Bool {
		vertical == .secondary
	}

	var location: UnitPoint {
		.init(x: horizontal.location, y: vertical.location)
	}
}


/**
A position on a rectangle.

Primary means left or top, secondary means right or bottom. Center is in the center.
*/
enum Side: Hashable {
	case primary
	case center
	case secondary

	/**
	 Location in the cop, from 0-1
	 */
	var location: Double {
		switch self {
		case .primary:
			0
		case .center:
			0.5
		case .secondary:
			1
		}
	}
}
