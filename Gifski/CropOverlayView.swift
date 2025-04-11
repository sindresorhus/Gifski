//
//  CropScreen.swift
//  Gifski
//
//  Created by Michael Mulet on 3/23/25.

import SwiftUI
import AVFoundation
import AVKit

fileprivate let cornerWidthHeight = 20.0


struct CropOverlayView: View {
	@Binding var cropRect: CropRect
	var editable: Bool

	@State private var dragMode = DragMode.normal
	@State private var lastDrag: CGSize = .zero

	@State private var isDragging = false

	@State private var updateCropRect = UpdateCropRect()

	/// This is a cache of the isMovableByWindowBackground
	/// property of the current window.
	/// This is an actual good case for Bool?
	/// Because it is a boolean value that at times
	/// may be unset. So I'm turning off the linter here
	// swiftlint:disable:next discouraged_optional_boolean
	@State private var windowIsMovable: Bool?

	var body: some View {
		GeometryReader { geometry in
			let frame = geometry.frame(in: .local)
			let cropFrame = CGRect(
				x: frame.width * cropRect.x,
				y: frame.height * cropRect.y,
				width: frame.width * cropRect.width,
				height: frame.height * cropRect.height
			)
			ZStack {
				Canvas { context, size in
					let path = Path { path in
						path.addRect(.init(origin: .zero, size: size))
					}
					context.fill(path, with: .color(.black.opacity(0.5)))
					let holePath = Path { path in
						path.addRect(
							.init(
								x: size.width * cropRect.x,
								y: size.height * cropRect.y,
								width: size.width * cropRect.width,
								height: size.height * cropRect.height
							)
						)
					}
					context.blendMode = .clear
					context.fill(holePath, with: .color(.black))
					if editable {
						context.blendMode = .normal
						context.stroke(holePath, with: .color(.white.opacity(0.75)), lineWidth: 2)
					}
				}
				.pointerStyle(isDragging ? .grabActive : .grabIdle)
				.contentShape(
					Path { path in
						path.addRect(cropFrame.insetBy(dx: 5, dy: 5))
					}
				)
				.gesture(
					editable ?
					DragGesture()
						.onChanged { value in
							isDragging = true
							updateCropRect.beginDrag(withIntialCropRect: cropRect)
							cropRect = updateCropRect.newCropRectFromDrag(
								drag: value,
								frame: frame,
								position: .center,
								dragMode: .normal,
								endDrag: false
							) ?? cropRect
						}
						.onEnded { value in
							isDragging = false
							cropRect = updateCropRect.newCropRectFromDrag(
								drag: value,
								frame: frame,
								position: .center,
								dragMode: .normal,
								endDrag: true
							) ?? cropRect
						}
					: nil
				)

				if isDragging {
					DraggingSections(cropFrame: cropFrame)
						.stroke(Color.white)
						.allowsHitTesting(false)
				}
				if editable {
					ForEach(HandlePosition.allCases, id: \.self) { position in
						if position != .center {
							HandleView(
								position: position,
								cropRect: $cropRect,
								frame: frame,
								cropFrame: cropFrame,
								dragMode: dragMode,
								isDragging: $isDragging
							)
						}
					}
				}
			}
		}
		.onAppear {
			let windowIsMovable = SSApp.swiftUIMainWindow?.isMovableByWindowBackground
			SSApp.swiftUIMainWindow?.isMovableByWindowBackground = false
			Task {
				@MainActor in
				self.windowIsMovable = windowIsMovable
			}
		}
		.onModifierKeysChanged(mask: [.option, .shift]) { _, new in
			self.dragMode = {
				if new.contains(.option) {
					if new.contains(.shift) {
						return .aspectRatioLockScale
					}
					return .symmetric
				}
				if new.contains(.shift) {
					return .scale
				}
				return .normal
			}()
		}
		.onDisappear {
			guard let oldSetting = windowIsMovable else {
				return
			}
			SSApp.swiftUIMainWindow?.isMovableByWindowBackground = oldSetting
		}
	}

	private struct DraggingSections: Shape {
		var cropFrame: CGRect
		func path(in rect: CGRect) -> Path {
			var path = Path()

			path.move(to: CGPoint(x: cropFrame.minX + cropFrame.width / 3.0, y: cropFrame.minY))
			path.addLine(to: CGPoint(x: cropFrame.minX + cropFrame.width / 3.0, y: cropFrame.maxY))

			path.move(to: CGPoint(x: cropFrame.minX + 2.0 * cropFrame.width / 3.0, y: cropFrame.minY))
			path.addLine(to: CGPoint(x: cropFrame.minX + 2.0 * cropFrame.width / 3.0, y: cropFrame.maxY))

			path.move(to: CGPoint(x: cropFrame.minX, y: cropFrame.minY + cropFrame.height / 3.0))
			path.addLine(to: CGPoint(x: cropFrame.maxX, y: cropFrame.minY + cropFrame.height / 3.0))

			path.move(to: CGPoint(x: cropFrame.minX, y: cropFrame.minY + 2.0 * cropFrame.height / 3.0))
			path.addLine(to: CGPoint(x: cropFrame.maxX, y: cropFrame.minY + 2.0 * cropFrame.height / 3.0))

			return path
		}
	}

	enum HandlePosition: CaseIterable {
		case topLeft
		case topRight
		case bottomLeft
		case bottomRight
		case center
		case top
		case left
		case right
		case bottom


		var isVertical: Bool {
			self == .top || self == .bottom
		}

		private var pointerPosition: FrameResizePosition {
			switch self {
			case .bottom:
				return .bottom
			case .topRight:
				return .topTrailing
			case .topLeft:
				return .topLeading
			case .bottomRight:
				return .bottomTrailing
			case .bottomLeft:
				return .bottomLeading
			case .left:
				return .leading
			case .right:
				return .trailing
			case .center:
				return .top
			case .top:
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

	private struct HandleView: View {
		let position: HandlePosition
		@Binding var cropRect: CropRect
		let frame: CGRect
		var cropFrame: CGRect
		var dragMode: DragMode
		@Binding  var isDragging: Bool

		private let cornerLineWidth = 3.0

		@State private var updateCropRect = UpdateCropRect()


		var body: some View {
			Group {
				if [.top, .left, .right, .bottom].contains(position) {
					sideView
				} else {
					ZStack {
						CornerLine(corner: position, lineWidth: cornerLineWidth)
							.stroke(Color.white, lineWidth: cornerLineWidth)
							.contentShape(Rectangle())
							.pointerStyle(position.pointerStyle)
					}.frame(width: cornerWidthHeight, height: cornerWidthHeight)
				}
			}
			.position(handlePosition())
			.highPriorityGesture(
				DragGesture()
					.onChanged { value in
						isDragging = true
						updateCropRect.beginDrag(withIntialCropRect: cropRect)

						cropRect = updateCropRect.newCropRectFromDrag(
							drag: value,
							frame: frame,
							position: position,
							dragMode: dragMode,
							endDrag: false
						) ?? cropRect
					}
					.onEnded { value in
						isDragging = false
						cropRect = updateCropRect.newCropRectFromDrag(
							drag: value,
							frame: frame,
							position: position,
							dragMode: dragMode,
							endDrag: true
						) ?? cropRect
					}
			)
		}


		private var sideView: some View {
			ZStack {
				Color.clear
					.frame(
						width: sideViewWidth,
						height: sideViewHeight
					)
					.contentShape(
						Path { path in
							let hitBoxSize = 20.0
							if position.isVertical {
								path.addRect(.init(
									origin: .init(x: 0, y: -hitBoxSize / 2.0),
									width: sideViewWidth,
									height: hitBoxSize
								))
								return
							}
							path.addRect(.init(
								origin: .init(x: -hitBoxSize / 2.0, y: 0),
								width: hitBoxSize,
								height: sideViewHeight
							))
						}
					)
					.pointerStyle(position.pointerStyle)
			}
		}
		private var sideViewWidth: Double {
			if position.isVertical {
				return max(0.0, cropFrame.width - cornerWidthHeight * 2.0)
			}
			return 2.0
		}
		private var sideViewHeight: Double {
			if position.isVertical {
				return 2.0
			}
			return max(0.0, cropFrame.height - cornerWidthHeight * 2.0)
		}

		private var size: CGSize {
			switch position {
			case .topLeft, .topRight, .bottomLeft, .bottomRight, .center:
				return .init(width: cornerWidthHeight, height: cornerWidthHeight)
			case .top, .bottom:
				return .init(width: cropRect.width - cornerWidthHeight, height: cornerWidthHeight)
			case .left, .right:
				return .init(width: cornerWidthHeight, height: cropRect.height - cornerWidthHeight)
			}
		}

		private func handlePosition() -> CGPoint {
			let inset = (cornerWidthHeight + cornerLineWidth) / 2.0
			let insetFrame = cropFrame.insetBy(dx: inset, dy: inset)
			switch position {
			case .topLeft:
				return CGPoint(x: insetFrame.minX, y: insetFrame.minY)
			case .topRight:
				return CGPoint(x: insetFrame.maxX, y: insetFrame.minY)
			case .bottomRight:
				return CGPoint(x: insetFrame.maxX, y: insetFrame.maxY)
			case .bottomLeft:
				return CGPoint(x: insetFrame.minX, y: insetFrame.maxY)

			case .center:
				return CGPoint(x: cropFrame.midX, y: cropFrame.midY)
			case .top:
				return CGPoint(x: cropFrame.midX, y: cropFrame.minY)
			case .left:
				return CGPoint(x: cropFrame.minX, y: cropFrame.midY)
			case .right:
				return CGPoint(x: cropFrame.maxX, y: cropFrame.midY)
			case .bottom:
				return CGPoint(x: cropFrame.midX, y: cropFrame.maxY)
			}
		}
	}


	private struct CornerLine: Shape {
		var corner: HandlePosition
		var lineWidth: Double
		func path(in rect: CGRect) -> Path {
			var path = Path()
			let tabSize = lineWidth
			switch corner {
			case .topLeft:
				path.move(to: CGPoint(x: rect.minX - tabSize, y: rect.maxY))

				path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
				path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
				path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

				path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - tabSize))
			case .topRight:
				path.move(to: CGPoint(x: rect.minX, y: rect.minY - tabSize))

				path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
				path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
				path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

				path.addLine(to: CGPoint(x: rect.maxX + tabSize, y: rect.maxY))

			case .bottomRight:
				path.move(to: CGPoint(x: rect.maxX + tabSize, y: rect.minY))

				path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
				path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
				path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

				path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY + tabSize))
			case .bottomLeft:
				path.move(to: CGPoint(x: rect.maxX, y: rect.maxY + tabSize))

				path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
				path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
				path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

				path.addLine(to: CGPoint(x: rect.minX - tabSize, y: rect.minY))
			case .center, .top, .left, .right, .bottom:
				return path
			}
			return path
		}
	}


	private class UpdateCropRect {
		private var beginDragCropRect: CropRect?

		func beginDrag(withIntialCropRect cropRect: CropRect){
			guard beginDragCropRect == nil else {
				return
			}
			beginDragCropRect = cropRect
		}

		func newCropRectFromDrag(
			drag: DragGesture.Value,
			frame: CGRect,
			position: HandlePosition,
			dragMode: DragMode,
			endDrag: Bool
		) -> CropRect? {
			defer {
				if endDrag {
					beginDragCropRect = nil
				}
			}

			guard let cropRectAtBeginOfDrag = beginDragCropRect else {
				assertionFailure()
				return nil
			}

			let dragStartAnchor: UnitPoint = {
				switch position {
				case .bottom, .right, .center, .left, .top:
					return .init(x: drag.startLocation.x / frame.width, y: drag.startLocation.y / frame.height)
				case .topLeft:
					return .init(x: cropRectAtBeginOfDrag.origin.x, y: cropRectAtBeginOfDrag.origin.y)
				case .topRight:
					return .init(x: (cropRectAtBeginOfDrag.origin.x + cropRectAtBeginOfDrag.width), y: cropRectAtBeginOfDrag.origin.y)
				case .bottomRight:
					return .init(x: (cropRectAtBeginOfDrag.origin.x + cropRectAtBeginOfDrag.width), y: cropRectAtBeginOfDrag.origin.y + cropRectAtBeginOfDrag.height)
				case .bottomLeft:
					return .init(x: cropRectAtBeginOfDrag.origin.x, y: cropRectAtBeginOfDrag.origin.y + cropRectAtBeginOfDrag.height)
				}
			}()

			let dragLocation: UnitPoint = .init(
				x: drag.location.x.clamped(from: frame.minX, to: frame.maxX) / frame.width,
				y: drag.location.y.clamped(from: frame.minY, to: frame.maxY) / frame.height
			)

			let dx = dragLocation.x - dragStartAnchor.x
			let dy = dragLocation.y - dragStartAnchor.y

			if position == .center {
				var outRect = cropRectAtBeginOfDrag
				/// 0.0 = outRect.x + minDX
				/// 0.0 - outRect.x = minDX
				/// 1.0 = outRect.x + outRect.width + maxDX
				/// 1.0 - outRect.x - outRect.width = maxDX
				let clampledDX = dx.clamped(from: -outRect.x, to: 1.0 - outRect.x - outRect.width)
				let clampedDY = dy.clamped(from: -outRect.y, to: 1.0 - outRect.y - outRect.height)

				outRect.x += clampledDX
				outRect.y += clampedDY



				return outRect
			}
			switch dragMode {
			case .normal:
				return applyNormal(
					position: position,
					cropRectAtBeginOfDrag: cropRectAtBeginOfDrag,
					frame: frame,
					dx: dx,
					dy: dy
				)
			case .symmetric:
				return applySymmetric(
					position: position,
					cropRectAtBeginOfDrag: cropRectAtBeginOfDrag,
					frame: frame,
					dx: dx,
					dy: dy
				)
			case .scale:
				return applyScale(
					position: position,
					cropRectAtBeginOfDrag: cropRectAtBeginOfDrag,
					frame: frame,
					dx: dx,
					dy: dy
				)
			case .aspectRatioLockScale:
				return applyAspectRatioLock(
					position: position,
					cropRectAtBeginOfDrag: cropRectAtBeginOfDrag,
					frame: frame,
					dragLocation: dragLocation
				)
			}
		}
		private func applyAspectRatioLock(
			position: HandlePosition,
			cropRectAtBeginOfDrag rect: CropRect,
			frame: CGRect,
			dragLocation: UnitPoint
		) -> CropRect {
			let dx = abs(dragLocation.x - rect.midX)
			let dy = abs(dragLocation.y - rect.midY)
			let rawScale: Double = {
				let scaleWidth = dx / (rect.width / 2)
				let scaleHeight = dy / (rect.height / 2)
				return max(scaleWidth, scaleHeight)
			}()

			let minScale: Double = {
				let minWidth = self.minWidth(frame: frame)
				let minHeight = self.minHeight(frame: frame)

				if rect.height < rect.width {
					return minHeight / rect.height
				}
				return minWidth / rect.width
			}()

			let maxScale: Double = {
				/// top and left sides
				/// x = rect.midX - scale * rect.width / 2
				/// 0 = rect.midX - maxScale * rect.width / 2
				/// - rect.midX = - maxScale * rect.width / 2
				/// rect.midX = maxScale * rect.width / 2
				/// rect.midX / (rect.width / 2) = maxScale
				/// 2.0 * rect.midX / rect.width = maxScale

				var maxScale: Double = 2.0 * rect.midX / rect.width
				maxScale = min(maxScale, 2.0 * rect.midY / rect.height)

				/// right and bottom sides
				/// x = rect.midX + scale * rect.width / 2
				/// 1.0 = rect.midX + maxScale * rect.width / 2
				/// 1.0 - rect.midX  = maxScale * rect.width / 2
				/// 1.0 - rect.midX / (rect.width / 2) = maxScale
				maxScale = min(maxScale, (1.0 - rect.midX) / (rect.width / 2))
				maxScale = min(maxScale, (1.0 - rect.midY) / (rect.height / 2))
				return maxScale
			}()


			let scale = minScale < maxScale ? rawScale.clamped(from: minScale, to: maxScale) : 1.0

			var outRect = rect

			outRect.width *= scale
			outRect.height *= scale
			outRect.x = rect.midX - outRect.width / 2
			outRect.y = rect.midY - outRect.height / 2
			return outRect
		}

		private func applyNormal(
			position: HandlePosition,
			cropRectAtBeginOfDrag cropRect: CropRect,
			frame: CGRect,
			dx rawDX: Double,
			dy rawDY: Double
		) -> CropRect {
			var outRect = cropRect
			let minWidth = self.minWidth(frame: frame)
			let minHeight = self.minHeight(frame: frame)

			switch position {
			case .topLeft:
				let dx = rawDX.clamped(from: -cropRect.x, to: outRect.width - minWidth)
				let dy = rawDY.clamped(from: -cropRect.y, to: outRect.height - minHeight)
				outRect.x += dx
				outRect.y += dy
				outRect.width -= dx
				outRect.height -= dy
			case .topRight:
				let dx = rawDX.clamped(from: -cropRect.width + minWidth, to: (1 - cropRect.x) - cropRect.width)
				let dy = rawDY.clamped(from: -cropRect.y, to: cropRect.height - minHeight)
				outRect.width += dx
				outRect.y += dy
				outRect.height -= dy
			case .bottomLeft:
				let dx = rawDX.clamped(from: -cropRect.x, to: cropRect.width - minWidth)
				let dy = rawDY.clamped(from: -cropRect.height + minHeight, to: (1 - cropRect.y) - cropRect.height)
				outRect.x += dx
				outRect.width -= dx
				outRect.height += dy
			case .bottomRight:
				let dx = rawDX.clamped(from: -cropRect.width + minWidth, to: (1 - cropRect.x) - cropRect.width)
				let dy = rawDY.clamped(from: -cropRect.height + minHeight, to: (1 - cropRect.y) - cropRect.height)
				outRect.width += dx
				outRect.height += dy
			case .top:
				let dy = rawDY.clamped(from: -cropRect.y, to: cropRect.height - minHeight)
				outRect.y += dy
				outRect.height -= dy
			case .left:
				let dx = rawDX.clamped(from: -cropRect.x, to: cropRect.width - minWidth)
				outRect.x += dx
				outRect.width -= dx
			case .right:
				let dx = rawDX.clamped(from: -cropRect.width + minWidth, to: (1 - cropRect.x) - cropRect.width)
				outRect.width += dx
			case .bottom:
				let dy = rawDY.clamped(from: -cropRect.height + minHeight, to: (1 - cropRect.y) - cropRect.height)
				outRect.height += dy
			case .center:
				break
			}
			return outRect
		}

		private  func applySymmetric(
			position: HandlePosition,
			cropRectAtBeginOfDrag cropRect: CropRect,
			frame: CGRect,
			dx rawDX: Double,
			dy rawDY: Double
		) -> CropRect {
			var outRect = cropRect
			let minWidth = self.minWidth(frame: frame)
			let minHeight = self.minHeight(frame: frame)

			switch position {
			case .topLeft:

				let lowerDx = max(-cropRect.x, cropRect.x + cropRect.width - 1)  // Ensures right edge stays ≤1
				let upperDx = (cropRect.width - minWidth) / 2
				let dx = rawDX.clamped(from: lowerDx, to: upperDx)

				let lowerDy = max(-cropRect.y, cropRect.y + cropRect.height - 1)
				let upperDy = (cropRect.height - minHeight) / 2
				let dy = rawDY.clamped(from: lowerDy, to: upperDy)

				outRect.x += dx
				outRect.y += dy
				outRect.width -= 2 * dx
				outRect.height -= 2 * dy
			case .topRight:
				let upperDx = min(cropRect.x, 1 - (cropRect.x + cropRect.width))
				let lowerDx = (minWidth - cropRect.width) / 2
				let dx = rawDX.clamped(from: lowerDx, to: upperDx)

				let lowerDy = max(-cropRect.y, cropRect.y + cropRect.height - 1)
				let upperDy = (cropRect.height - minHeight) / 2
				let dy = rawDY.clamped(from: lowerDy, to: upperDy)

				outRect.x -= dx
				outRect.width += 2 * dx
				outRect.y += dy
				outRect.height -= 2 * dy
			case .bottomLeft:
				let lowerDx = max(-cropRect.x, cropRect.x + cropRect.width - 1)
				let upperDx = (cropRect.width - minWidth) / 2
				let dx = rawDX.clamped(from: lowerDx, to: upperDx)

				let upperDy = min(cropRect.y, 1 - (cropRect.y + cropRect.height))
				let lowerDy = (minHeight - cropRect.height) / 2
				let dy = rawDY.clamped(from: lowerDy, to: upperDy)

				outRect.x += dx
				outRect.width -= 2 * dx
				outRect.y -= dy
				outRect.height += 2 * dy

			case .bottomRight:
				let upperDx = min(cropRect.x, 1 - (cropRect.x + cropRect.width))
				let lowerDx = (minWidth - cropRect.width) / 2
				let dx = rawDX.clamped(from: lowerDx, to: upperDx)

				let upperDy = min(cropRect.y, 1 - (cropRect.y + cropRect.height))
				let lowerDy = (minHeight - cropRect.height) / 2
				let dy = rawDY.clamped(from: lowerDy, to: upperDy)

				outRect.x -= dx
				outRect.width += 2 * dx
				outRect.y -= dy
				outRect.height += 2 * dy

			case .top:
				let lowerDy = max(-cropRect.y, cropRect.y + cropRect.height - 1)
				let upperDy = (cropRect.height - minHeight) / 2
				let dy = rawDY.clamped(from: lowerDy, to: upperDy)
				outRect.y += dy
				outRect.height -= 2 * dy

			case .left:
				let lowerDx = max(-cropRect.x, cropRect.x + cropRect.width - 1)
				let upperDx = (cropRect.width - minWidth) / 2
				let dx = rawDX.clamped(from: lowerDx, to: upperDx)
				outRect.x += dx
				outRect.width -= 2 * dx

			case .right:
				let upperDx = min(cropRect.x, 1 - (cropRect.x + cropRect.width))
				let lowerDx = (minWidth - cropRect.width) / 2
				let dx = rawDX.clamped(from: lowerDx, to: upperDx)
				outRect.x -= dx
				outRect.width += 2 * dx
			case .bottom:
				let upperDy = min(cropRect.y, 1 - (cropRect.y + cropRect.height))
				let lowerDy = (minHeight - cropRect.height) / 2
				let dy = rawDY.clamped(from: lowerDy, to: upperDy)
				outRect.y -= dy
				outRect.height += 2 * dy
			case .center:
				break
			}
			return outRect
		}

		private func applyScale(
			position: HandlePosition,
			cropRectAtBeginOfDrag cropRect: CropRect,
			frame: CGRect,
			dx: Double,
			dy: Double
		) -> CropRect {
			let oldWidth = cropRect.width
			let oldHeight = cropRect.height
			let minWidth = self.minWidth(frame: frame)
			let minHeight = self.minHeight(frame: frame)

			// Compute scale based on handle if not center.
			var scale: Double
			switch position {
			case .center:
				return cropRect
			case .topLeft:
				scale = ((1 - dx / oldWidth) + (1 - dy / oldHeight)) / 2
			case .topRight:
				scale = ((1 + dx / oldWidth) + (1 - dy / oldHeight)) / 2
			case .bottomLeft:
				scale = ((1 - dx / oldWidth) + (1 + dy / oldHeight)) / 2
			case .bottomRight:
				scale = ((1 + dx / oldWidth) + (1 + dy / oldHeight)) / 2
			case .top:
				scale = 1 - dy / oldHeight
			case .bottom:
				scale = 1 + dy / oldHeight
			case .left:
				scale = 1 - dx / oldWidth
			case .right:
				scale = 1 + dx / oldWidth
			}

			let anchor: CGPoint
			switch position {
			case .topLeft:
				anchor = CGPoint(x: cropRect.x + cropRect.width, y: cropRect.y + cropRect.height)
			case .topRight:
				anchor = CGPoint(x: cropRect.x, y: cropRect.y + cropRect.height)
			case .bottomLeft:
				anchor = CGPoint(x: cropRect.x + cropRect.width, y: cropRect.y)
			case .bottomRight:
				anchor = CGPoint(x: cropRect.x, y: cropRect.y)
			case .top:
				anchor = CGPoint(x: cropRect.x + cropRect.width / 2, y: cropRect.y + cropRect.height)
			case .bottom:
				anchor = CGPoint(x: cropRect.x + cropRect.width / 2, y: cropRect.y)
			case .left:
				anchor = CGPoint(x: cropRect.x + cropRect.width, y: cropRect.y + cropRect.height / 2)
			case .right:
				anchor = CGPoint(x: cropRect.x, y: cropRect.y + cropRect.height / 2)
			case .center:
				anchor = CGPoint(x: cropRect.x + cropRect.width / 2, y: cropRect.y + cropRect.height / 2)
			}
			/// let leftEdge = newX
			/// 0.0 = anchor.x - (anchor.x - cropRect.x) * maxScale
			/// -anchor.x = -(anchor.x - cropRect.x) * maxScale
			/// anchor.x = (anchor.x - cropRect.x) * maxScale
			/// anchor.x / (anchor.x - cropRect.x) = maxScale
			if anchor.x > 0.001 {
				scale = min(anchor.x / max(anchor.x - cropRect.x, 0.001), scale)
			}
			if anchor.y > 0.001 {
				scale = min(anchor.y / max(anchor.y - cropRect.y, 0.001), scale)
			}

			/// let rightEdge = newX + newWidth
			/// 1.0 = anchor.x - (anchor.x - cropRect.x) * maxScale + oldWidth * maxScale
			/// 1.0 - anchor.x = (-anchor.x + cropRect.x + oldWidth) * maxScale
			/// (1.0 - anchor.x)/(-anchor.x + cropRect.x + oldWidth) = maxScale
			if anchor.x < 0.999 {
				scale = min((1.0 - anchor.x) / max(-anchor.x + cropRect.x + oldWidth, 0.001), scale)
			}
			if anchor.y < 0.999 {
				scale = min((1.0 - anchor.y) / max(-anchor.y + cropRect.y + oldHeight, 0.001), scale)
			}

			scale = max(minWidth / oldWidth, scale)
			scale = max(minHeight / oldHeight, scale)


			let newWidth = oldWidth * scale
			let newHeight = oldHeight * scale

			let newX = anchor.x - (anchor.x - cropRect.x) * scale
			let newY = anchor.y - (anchor.y - cropRect.y) * scale


			var outRect = cropRect
			outRect.x = newX
			outRect.y = newY
			outRect.width = newWidth
			outRect.height = newHeight
			return outRect
		}
		private func minWidth(frame: CGRect) -> Double {
			cornerWidthHeight * 2.0 / frame.width
		}
		private func minHeight(frame: CGRect) -> Double {
			cornerWidthHeight * 2.0 / frame.height
		}
	}
}
enum DragMode {
	case normal
	case symmetric
	case scale
	case aspectRatioLockScale
}
extension Color {
	static let cropSideWhite: Color = .init(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.75)
}
