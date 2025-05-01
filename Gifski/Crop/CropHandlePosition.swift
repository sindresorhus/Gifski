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

	var location: (Double, Double) {
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

	var sides: RectSides {
		switch self {
		case .top:
			return .init(horizontal: .center, vertical: .primary)
		case .topRight:
			return .init(horizontal: .secondary, vertical: .primary)
		case .right:
			return .init(horizontal: .secondary, vertical: .center)
		case .bottomRight:
			return .init(horizontal: .secondary, vertical: .secondary)
		case .bottom:
			return .init(horizontal: .center, vertical: .secondary)
		case .bottomLeft:
			return .init(horizontal: .primary, vertical: .secondary)
		case .left:
			return .init(horizontal: .primary, vertical: .center)
		case .topLeft:
			return .init(horizontal: .primary, vertical: .primary)
		case .center:
			return .init(horizontal: .center, vertical: .center)
		}
	}

	private var pointerPosition: FrameResizePosition {
		switch self {
		case .top:
			return .top
		case .topRight:
			return .topTrailing
		case .right:
			return .trailing
		case .bottomRight:
			return .bottomTrailing
		case .bottom:
			return .bottom
		case .bottomLeft:
			return .bottomLeading
		case .left:
			return .leading
		case .topLeft:
			return .topLeading
		case .center:
			return .top
		}
	}

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

	/**
	 is a control to move the crop vertically TODO, better name
	 */
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

	var location: (Double, Double) {
		(horizontal.location, vertical.location)
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
