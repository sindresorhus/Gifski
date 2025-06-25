import SwiftUI
import AVFoundation
import AVKit

struct CropOverlayView: View {
	@State private var dragMode = CropRect.DragMode.normal
	@State private var isDragging = false
	// swiftlint:disable:next discouraged_optional_boolean
	@State private var windowIsMovable: Bool?
	@State private var window: NSWindow?

	@Binding var cropRect: CropRect
	let dimensions: CGSize
	var editable: Bool

	var body: some View {
		GeometryReader { geometry in
			let frame = geometry.frame(in: .local)
			let cropFrame = cropRect.unnormalize(forDimensions: frame.size)
			ZStack {
				Canvas { context, size in
					// Darken the entire video by drawing a transparent black color, then "cut-out" the section of what we are cropping. If we are editing we then draw a white outline over our path
					let entireCanvasPath = Path { path in
						path.addRect(.init(origin: .zero, size: size))
					}

					context.fill(entireCanvasPath, with: .color(.black.opacity(0.5)))

					let holePath = Path { path in
						path.addRect(cropFrame)
					}

					context.blendMode = .clear
					context.fill(holePath, with: .color(.black))

					if editable {
						context.blendMode = .normal
						context.stroke(holePath, with: .color(.white), lineWidth: 1)
					}
				}
				if editable {
					Color
						.clear
						.contentShape(
							Path { path in
								path.addRect(cropFrame.insetBy(dx: 5, dy: 5))
							}
						)
						.pointerStyle(isDragging ? .grabActive : .grabIdle)
						.cropDragGesture(
							isDragging: $isDragging,
							cropRect: $cropRect,
							frame: frame,
							dimensions: dimensions,
							position: .center,
							dragMode: dragMode
						)
				}
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
								dimensions: dimensions,
								cropFrame: cropFrame,
								dragMode: dragMode,
								isDragging: $isDragging
							)
						}
					}
				}
			}
		}
		/**
		The setter is necessary because there are lifecycle changes not captured by the $binding.

		For example consider this:
		```swift
		struct SomeView: View {
			@State var window: NSWindow?

			var body: some View {
				Color.clear()
					.bindHostingWindow($window)
					.onDisappear {
						/*
						By the time this is called `window` is already nil
						*/
						assert(window == nil)
					}
					.accessHostingWindow { window in
						 /**
						 When view disappears this is never called.
						 */
					}
					.onChange(of: window) { old, new in
						 /**
						 When the view disappears this is never called.
						 */
					}
			}
		}
		```

		This is because on view disappear the following events happen in order:

		1. `viewDidMoveToWindow` with `window` == nil

		2. Then `onDisappear` is called

		∞. ` accessHostingWindow` and `onChange` are never called because SwiftUI does not build the view again when disappearing

		I need a custom setter to capture all changes before the the view disappears, and I can't use `accessHostingWindow` or `onChange(of:)` or `onDisappear`
		*/
		.bindHostingWindow(
			.init(
				get: {
					window
				},
				set: { newWindow in
					guard newWindow != window else {
						return
					}

					if let windowIsMovable {
						window?.isMovableByWindowBackground = windowIsMovable
					}

					windowIsMovable = newWindow?.isMovableByWindowBackground
					newWindow?.isMovableByWindowBackground = false
					window = newWindow
				}
			)
		)
		.onModifierKeysChanged(mask: [.option, .shift]) { _, new in
			dragMode = {
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
	}

	/**
	The four lines that divide your crop into sections that appear when dragging.
	*/
	private struct DraggingSections: Shape {
		var cropFrame: CGRect

		func path(in rect: CGRect) -> Path {
			var path = Path()

			for factor in [1.0 / 3.0, 2.0 / 3.0] {
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
		private static let cornerLineWidth = 3.0
		private static let cornerWidthHeight = 28.0

		let position: CropHandlePosition
		@Binding var cropRect: CropRect
		let frame: CGRect
		let dimensions: CGSize
		var cropFrame: CGRect
		var dragMode: CropRect.DragMode
		@Binding var isDragging: Bool

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
			.cropDragGesture(
				isDragging: $isDragging,
				cropRect: $cropRect,
				frame: frame,
				dimensions: dimensions,
				position: position,
				dragMode: dragMode
			)
		}

		/**
		Where to place this handle in the canvas. Top is at the top, bottom is at the bottom, etc.
		*/
		private var canvasPosition: CGPoint {
			let inset = (Self.cornerWidthHeight + Self.cornerLineWidth) / 2.0 - 3.0
			let adjustedFrame = position.isCorner ? cropFrame.insetBy(dx: inset, dy: inset) : cropFrame
			return CGPoint(
				x: adjustedFrame.minX + adjustedFrame.width * position.location.x,
				y: adjustedFrame.minY + adjustedFrame.height * position.location.y
			)
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
							width: sideViewSize.width,
							height: sideViewSize.height
						)
						.contentShape(
							Path { path in
								// A rectangle around the drag used to catch hits so we can drag.
								let hitBoxSize = 20.0
								if position.isVerticalOnlyHandle {
									path.addRect(.init(
										origin: .init(x: 0, y: -hitBoxSize / 2.0),
										width: sideViewSize.width,
										height: hitBoxSize
									))
									return
								}
								path.addRect(.init(
									origin: .init(x: -hitBoxSize / 2.0, y: 0),
									width: hitBoxSize,
									height: sideViewSize.height
								))
							}
						)
				}
			}

			private var sideViewSize: CGSize {
				switch position.isVerticalOnlyHandle {
				case true:
					CGSize(width: max(0.0, cropFrame.width - HandleView.cornerWidthHeight * 2.0), height: 2.0)
				case false:
					CGSize(width: 2.0, height: max(0.0, cropFrame.height - HandleView.cornerWidthHeight * 2.0))
				}
			}
		}

		private struct CornerLine: View {
			@Environment(\.displayScale) private var displayScale
			private let hitboxExtensionSize = 5.0

			let corner: CropHandlePosition

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
				let sx = corner.location.x * 2 - 1
				let sy = corner.location.y * 2 - 1
				return .init(width: sx * hitboxExtensionSize, height: sy * hitboxExtensionSize)
			}

			/**
			The bent line at the corners.
			*/
			private struct CornerLineShape: Shape {
				let displayScale: Double
				let corner: CropHandlePosition

				func path(in rect: CGRect) -> Path {
					var path = Path()

					guard
						!rect.width.isNaN,
						!rect.height.isNaN
					else {
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
