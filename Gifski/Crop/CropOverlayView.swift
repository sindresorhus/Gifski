//
//  CropScreen.swift
//  Gifski
//
//  Created by Michael Mulet on 3/23/25.

import SwiftUI
import AVFoundation
import AVKit


struct CropOverlayView: View {
	@Binding var cropRect: CropRect
	var editable: Bool
	@State private var dragMode = CropRect.DragMode.normal
	@State private var isDragging = false
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
					/**
					 Darken the entire video by drawing a transparent black color, then "cut-out" the section what we are cropping. If we are editing we then draw a white outline over our path
					 */
					let entireCanvasPath = Path { path in
						path.addRect(.init(origin: .zero, size: size))
					}
					context.fill(entireCanvasPath, with: .color(.black.opacity(0.5)))
					let holePath = Path { path in
						path.addRect( cropFrame )
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
				.editCropDragGesture(
					isDragging: $isDragging,
					cropRect: $cropRect,
					frame: frame,
					position: .center,
					dragMode: dragMode
				)

				if isDragging {
					DraggingSections(cropFrame: cropFrame)
						.stroke(Color.white)
						.allowsHitTesting(false)
				}
				if editable {
					ForEach(CropHandlePosition.allCases, id: \.self) { position in
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
	/**
	 The four lines that divide your crop into sections that appear when dragging.
	 */
	private struct DraggingSections: Shape {
		var cropFrame: CGRect

		func path(in rect: CGRect) -> Path {
			var path = Path()
			[1.0 / 3.0, 2.0 / 3.0].forEach { factor in
				let x = cropFrame.minX + cropFrame.width * factor
				path.move(to: CGPoint(x: x, y: cropFrame.minY))
				path.addLine(to: CGPoint(x: x, y: cropFrame.maxY))

				let y = cropFrame.minY + cropFrame.height * factor
				path.move(to: CGPoint(x: cropFrame.minX, y: y))
				path.addLine(to: CGPoint(x: cropFrame.maxX, y: y))
			}
			return path
		}
	}

	private struct HandleView: View {
		let position: CropHandlePosition
		@Binding var cropRect: CropRect
		let frame: CGRect
		var cropFrame: CGRect
		var dragMode: CropRect.DragMode
		@Binding  var isDragging: Bool

		private static let cornerLineWidth = 3.0
		private static let cornerWidthHeight = 28.0

		var body: some View {
			Group {
				if [.top, .left, .right, .bottom].contains(position) {
					SideHandleView(
						cropFrame: cropFrame,
						position: position
					)
				} else {
					CornerLine(corner: position)
				}
			}
			.pointerStyle(position.pointerStyle)
			.position(canvasPosition)
			.editCropDragGesture(
				isDragging: $isDragging,
				cropRect: $cropRect,
				frame: frame,
				position: position,
				dragMode: dragMode
			)
		}

		/**
		 where to put place this handle in the canvas. Top is at the top, bottom is at the bottom, etc.
		 */
		private var canvasPosition: CGPoint {
			let frame = {
				switch position {
				case .topLeft, .topRight, .bottomRight, .bottomLeft:
					let inset = (Self.cornerWidthHeight + Self.cornerLineWidth) / 2.0 - 3.0
					return cropFrame.insetBy(dx: inset, dy: inset)
				case .center, .top, .left, .right, .bottom:
					return cropFrame
				}
			}()
			let (x, y) = position.location
			return CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
		}


		/**
		 The handles for top, bottom, left, and right. They are invisible and used only to change the pointer and handle drags.
		 */
		struct SideHandleView: View {
			var cropFrame: CGRect
			var position: CropHandlePosition
			var body: some View {
				ZStack {
					Color.clear
						.frame(
							width: sideViewWidth,
							height: sideViewHeight
						)
						.contentShape(
							Path { path in
								/**
								 A rectangle around the drag used to catch hits so we can drag.
								 */
								let hitBoxSize = 20.0
								if position.isVerticalOnlyHandle {
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
				}
			}
			private var sideViewWidth: Double {
				if position.isVerticalOnlyHandle {
					return max(0.0, cropFrame.width - HandleView.cornerWidthHeight * 2.0)
				}
				return 2.0
			}

			private var sideViewHeight: Double {
				if position.isVerticalOnlyHandle {
					return 2.0
				}
				return max(0.0, cropFrame.height - HandleView.cornerWidthHeight * 2.0)
			}
		}


		private struct CornerLine: View {
			@Environment(\.displayScale) private var displayScale
			var corner: CropHandlePosition

			let hitboxExtensionSize = 10.0

			var body: some View {
				CornerLineShape(displayScale: displayScale, corner: corner)
					.stroke(Color.white, lineWidth: HandleView.cornerLineWidth)
					.contentShape(
						Rectangle()
						.size(.init(widthHeight: HandleView.cornerWidthHeight + hitboxExtensionSize))
						.offset(offset)
					)
					.frame(width: HandleView.cornerWidthHeight, height: HandleView.cornerWidthHeight)
			}
			var offset: CGSize {
				let (locationX, locationY) = corner.location
				let sx = locationX * 2 - 1
				let sy = locationY * 2 - 1
				return .init(width: sx * hitboxExtensionSize, height: sy * hitboxExtensionSize)
			}

			/**
			 The bent line at the corners.
			 */
			private struct CornerLineShape: Shape {
				var displayScale: Double
				var corner: CropHandlePosition
				func path(in rect: CGRect) -> Path {
					var path = Path()
					guard !rect.width.isNaN, !rect.height.isNaN else {
						return path
					}
					let tab = displayScale == 1.0 ? 0.0 : -2.0
					let insetRect = rect.insetBy(dx: 3, dy: 3)
					let inset = -3.0

					let base: [CGPoint] = [
						.init(x: -tab, y: insetRect.height),
						.init(x: 0 - inset, y: insetRect.height),
						.init(x: 0 - inset, y: 0 - inset),
						.init(x: insetRect.width, y: 0 - inset),
						.init(x: insetRect.width, y: -tab)
					]

					let transforms: [CropHandlePosition: CGAffineTransform] = [
						.topLeft: .identity.translatedBy(x: rect.minX, y: rect.minY),
						.topRight: CGAffineTransform(scaleX: -1, y: 1)
						.translatedBy(x: -rect.minX - rect.width, y: rect.minY),
						.bottomRight: CGAffineTransform(scaleX: -1, y: -1)
						.translatedBy(x: -rect.minX - rect.width, y: -rect.minY - rect.height),
						.bottomLeft: CGAffineTransform(scaleX: 1, y: -1)
						.translatedBy(x: rect.minX, y: -rect.minY - rect.height)
					]
					guard let transform = transforms[corner] else {
						return path
					}
					path.move(to: base[0].applying(transform))
					for point in base.dropFirst() {
						path.addLine(to: point.applying(transform))
					}
					return path
				}
			}
		}
	}
}

extension Color {
	static let cropSideWhite: Color = .init(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.75)
}
