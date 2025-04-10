//
//  CropScreen.swift
//  Gifski
//
//  Created by Michael Mulet on 3/23/25.

import SwiftUI
import AVFoundation
import AVKit

fileprivate let cornerWidthHeight = 30.0

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

	@State private var flagsMonitor: Any?

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
				}

				if isDragging {
					DraggingSections(cropFrame: cropFrame)
						.stroke()
						.allowsHitTesting(false)
				}
				if editable {
					CusomCursor(cursor: isDragging ? .closedHand : .openHand)
						.contentShape(
							Path { path in
								path.addRect(cropFrame)
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
			/// Stop the entire window from dragging
			/// when we drag on the the crop mask
			/// I would love a pure SwitUI way to do
			/// this, do you know of one?
			let windowIsMovable = SSApp.swiftUIMainWindow?.isMovableByWindowBackground
			SSApp.swiftUIMainWindow?.isMovableByWindowBackground = false
			Task {
				@MainActor in
				self.windowIsMovable = windowIsMovable
			}
			if let flagsMonitor {
				NSEvent.removeMonitor(flagsMonitor)
			}
			flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
				Task {
					@MainActor in
					if event.modifierFlags.contains(.shift) {
						self.dragMode = .scale
						return
					}
					if event.modifierFlags.contains(.option) {
						self.dragMode = .symmetric
						return
					}
					self.dragMode = .normal
					return
				}
				return event
			}
		}
		.onDisappear {
			if let flagsMonitor {
				NSEvent.removeMonitor(flagsMonitor)
				self.flagsMonitor = nil
			}
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
		@available(macOS 15, *)
		var cursorPosition: NSCursor.FrameResizePosition {
			switch self {
			case .bottom:
				return .bottom
			case .topRight:
				return .topRight
			case .topLeft:
				return .topLeft
			case .bottomRight:
				return .bottomRight
			case .bottomLeft:
				return .bottomLeft
			case .left:
				return .left
			case .right:
				return .right
			case .center:
				return .top
			case .top:
				return .top
			}
		}

		var cursor: NSCursor {
			if self == .center {
				return .openHand
			}
			if #available(macOS 15, *) {
				return .frameResize(position: cursorPosition, directions: .all)
			}
			switch self {
			case .bottom, .top:
				return .resizeUpDown
			case .bottomLeft, .bottomRight, .left, .right, .topLeft, .topRight:
				return .resizeLeftRight
			case .center:
				return .openHand
			}
		}
	}

	private class CustomCursorView: NSView {
		var cursor: NSCursor = .arrow

		override func resetCursorRects() {
			super.resetCursorRects()
			addCursorRect(
				self.bounds,
				cursor: cursor
			)
		}
	}

	/// Backwards compaitble way for custom cursor
	///
	/// Normally I would just do something like
	/// ```swift
	///	var body: some View {
	///		Rectangle()
	///		.onHover {
	///			hover in
	///			if hover {
	///				// also tried with: NSApp.windows.forEach { w in w.disableCursorRects }
	///				NSCursor.openHand.set()
	///			} else {
	///				NSCursor.arrow.set()
	///				//  NSApp.windows.forEach { w in w.enableCursorRects }
	///
	///			}
	///		}
	///	}
	///	```
	/// but this doesn't work when the CropOverlayView embedeed
	/// in the TrimmingAVPlayer via a NSHosting View
	///
	/// We need this class instead.
	/// If the app moves to macOS 15 we may be able to
	/// use the  pointerStyle the modifier
	private struct CusomCursor: NSViewRepresentable {
		var cursor: NSCursor
		func makeNSView(context: Context) -> CustomCursorView {
			CustomCursorView()
		}
		func updateNSView(_ nsView: CustomCursorView, context: Context) {
			nsView.cursor = cursor
		}
	}

	private struct HandleView: View {
		let position: HandlePosition
		@Binding var cropRect: CropRect
		let frame: CGRect
		var cropFrame: CGRect
		var dragMode: DragMode
		@Binding  var isDragging: Bool

		private let cornerLineWidth = 5.0

		@State private var updateCropRect = UpdateCropRect()


		var body: some View {
			Group {
				if [.top, .left, .right, .bottom].contains(position) {
					sideView
				} else {
					ZStack {
						CornerLine(corner: position, lineWidth: cornerLineWidth)
							.stroke(lineWidth: cornerLineWidth)
						CusomCursor(cursor: position.cursor)
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
				Rectangle()
					.fill(Color.cropSideWhite)
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
				CusomCursor(cursor: position.cursor)
					.frame(
						width: position.isVertical ? sideViewWidth : 20.0,
						height: position.isVertical ? 20.0 : sideViewHeight
					)
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
			let translationX = drag.location.x.clamped(from: frame.minX, to: frame.maxX) - drag.startLocation.x
			let translationY = drag.location.y.clamped(from: frame.minY, to: frame.maxY) - drag.startLocation.y

			let dx = translationX / frame.width
			let dy = translationY / frame.height


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
			}
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
	var handleColor: Color {
		switch self {
		case .normal:
				.white
		case .symmetric:
				.blue
		case .scale:
				.yellow
		}
	}
}
struct CropCornerShape: View {
	var dragMode: DragMode
	var body: some View {
		switch dragMode {
		case .normal:
			Circle().fill(dragMode.handleColor)
		case .symmetric:
			Rectangle().fill(dragMode.handleColor)
		case .scale:
			RoundedRectangle(cornerSize: .init(widthHeight: 5)).fill(dragMode.handleColor)
		}
	}
}
extension Color {
	static let cropSideWhite: Color = .init(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.75)
}
