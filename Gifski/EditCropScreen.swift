//
//  CropScreen.swift
//  Gifski
//
//  Created by Michael Mulet on 3/23/25.

import SwiftUI
import AVFoundation
import AVKit
struct EditCropScreen: View {
	/// For performance reasons
	/// we cannot use these binding directly
	/// (when they are connected to @Defaults
	/// it slows everything way way down)
	/// so we cache the outputState in
	/// the non-output versions and set
	/// them on view dissapear
	@Binding private var outputCrop: Bool
	@Binding private var outputCropRect: CropRect
	/**
	 There are 3 cases somone will open
	 the EditCropScreen
	 1. To turn on crop, in which case
	 we should set self.outputCrop
	 to true
	 2. To edit an existing crop, in which
	 setting crop to true won't
	 affect anything
	 3. To turn off crop, in which case,
	 crop is already on, so setting
	 crop to totrue wont' affect anything
	 again
	 Thus, we should set crop to true here
	 */
	@State private var crop = true
	@State private var cropRect: CropRect


	private var asset: AVAsset
	private var metadata: AVAsset.VideoMetadata
	private var bounceGIF: Bool

	/// This is a cache of the isMovableByWindowBackground
	/// property of the current window.
	/// This is an actual good case for Bool?
	/// Because it is a boolean value that at times
	/// may be unset. So I'm turning off the linter here
	@State private var windowIsMovable: Bool? // swiftlint:disable:this discouraged_optional_boolean
	@State private var dragMode = DragMode.normal

	@State private var flagsMonitor: Any?

	init(
		outputCrop: Binding<Bool>,
		outputCropRect: Binding<CropRect>,
		asset: AVAsset,
		metadata: AVAsset.VideoMetadata,
		bounceGIF: Bool
	) {
		self._outputCrop = outputCrop
		self._outputCropRect = outputCropRect
		self.asset = asset
		self.metadata = metadata
		self.bounceGIF = bounceGIF

		self._cropRect = State(initialValue: outputCropRect.wrappedValue)
	}


	var body: some View {
		VStack {
			ZStack {
				CheckerboardView()
				if crop {
					Color.black.opacity(0.5)
				}
				ZStack {
					TrimmingAVPlayer(
						asset: asset,
						controlsStyle: .none,
						loopPlayback: true,
						bouncePlayback: bounceGIF
					)
					if crop {
						CropOverlayView(
							cropRect: $cropRect,
							editable: true,
							dragMode: dragMode
						)
					}
				}
				.aspectRatio(metadata.dimensions.aspectRatio, contentMode: .fit)
				.scaleEffect(.init(width: 0.7, height: 0.7))
			}
			HStack {
				Form {
					HStack {
						Toggle("Crop", isOn: $crop)
							.toggleStyle(.checkbox)
						Spacer()
						Button("Reset") {
							crop = true
							cropRect = .initialCropRect
						}
					}
					HStack {
						CropCornerShape(dragMode: .normal).frame(width: 20, height: 20)
						Text("Drag to adjust the crop")
							.foregroundColor(.secondary)
					}.background(dragMode == .normal ? Color.blue.opacity(0.2) : Color.clear)

					HStack {
						CropCornerShape(dragMode: .symmetric).frame(width: 20, height: 20)
						Text("Shift + Drag for centered resizing")
							.foregroundColor(.secondary)
					}.background(dragMode == .symmetric ? Color.blue.opacity(0.2) : Color.clear)

					HStack {
						CropCornerShape(dragMode: .scale).frame(width: 20, height: 20)
						Text("Option + Drag to scale while maintaining the aspect ratio")
							.foregroundColor(.secondary)
					}.background(dragMode == .scale ? Color.blue.opacity(0.2) : Color.clear)
				}
				Form {
					Section(header: Text("Crop Presets")) {
						Menu("Select Preset") {
							Button("Top Half") {
								crop = true
								cropRect = CropRect(x: 0, y: 0, width: 1, height: 0.5)
							}
							Button("Bottom Half") {
								crop = true
								cropRect = CropRect(x: 0, y: 0.5, width: 1, height: 0.5)
							}
							Button("Left Half") {
								crop = true
								cropRect = CropRect(x: 0, y: 0, width: 0.5, height: 1)
							}
							Button("Right Half") {
								crop = true
								cropRect = CropRect(x: 0.5, y: 0, width: 0.5, height: 1)
							}
							Button("Center") {
								crop = true
								cropRect = CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
							}
						}
					}
				}
			}.padding(-12)
				.formStyle(.grouped)
				   .scrollContentBackground(.hidden)
				   .scrollDisabled(true)
				   .fixedSize()
		}
		.navigationTitle("Crop Video")
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
					if event.modifierFlags.contains(.option) {
						self.dragMode = .scale
						return
					}
					if event.modifierFlags.contains(.shift) {
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
			outputCrop = crop
			outputCropRect = cropRect
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
}

struct CropOverlayView: View {
	@Binding var cropRect: CropRect
	var editable: Bool
	var dragMode = DragMode.normal
	@State private var lastDrag: CGSize = .zero

	var body: some View {
		GeometryReader { geometry in
			let frame = geometry.frame(in: .local)
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
						context.stroke(holePath, with: .color(.white), lineWidth: 5)
					}
				}.contentShape(
					Path { path in
						let cropFrame = CGRect(
							x: frame.width * cropRect.x,
							y: frame.height * cropRect.y,
							width: frame.width * cropRect.width,
							height: frame.height * cropRect.height
						)
						path.addRect(cropFrame)
					}
				)
				.gesture(
					editable ?
					DragGesture()
						.onChanged { value in
							let delta = CGSize(
								width: value.translation.width - lastDrag.width,
								height: value.translation.height - lastDrag.height
							)
							lastDrag = value.translation
							let dx = delta.width / frame.width
							let dy = delta.height / frame.height
							cropRect.x += dx
							cropRect.y += dy
							cropRect.x = max(0, min(cropRect.x, 1 - cropRect.width))
							cropRect.y = max(0, min(cropRect.y, 1 - cropRect.height))
						}
						.onEnded { _ in
							lastDrag = .zero
						}
					: nil
				)
				if editable {
					ForEach(HandlePosition.allCases, id: \.self) { position in
						HandleView(
							position: position,
							cropRect: $cropRect,
							frame: frame,
							dragMode: dragMode
						)
					}
				}
			}
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
	}

	private struct HandleView: View {
		let position: HandlePosition
		@Binding var cropRect: CropRect
		let frame: CGRect
		var dragMode: DragMode

		@State private var currentDrag: CGSize = .zero



		var body: some View {
			Group {
				if [.top, .left, .right, .bottom].contains(position) {
					Rectangle()
						.fill(dragMode.handleColor)
						.frame(
							width: position.isVertical ? 30 : 20,
							height: position.isVertical ? 20 : 30
						)
				} else {
					Group {
						if position == .center {
							CropCornerShape(dragMode: .normal)
						} else {
							CropCornerShape(dragMode: dragMode)
						}
					}.frame(width: 30, height: 30)
				}
			}
			.position(handlePosition())
			.highPriorityGesture(
				DragGesture()
					.onChanged { value in
						updateCropRect(
							dragTranslation: value.translation,
							endDrag: false
						)
					}
					.onEnded { value in
						updateCropRect(
							dragTranslation: value.translation,
							endDrag: true
						)
					}
			)
		}

		private func handlePosition() -> CGPoint {
			let cropFrame = CGRect(
				x: frame.width * cropRect.x,
				y: frame.height * cropRect.y,
				width: frame.width * cropRect.width,
				height: frame.height * cropRect.height
			)

			switch position {
			case .topLeft:
				return CGPoint(x: cropFrame.minX, y: cropFrame.minY)
			case .topRight:
				return CGPoint(x: cropFrame.maxX, y: cropFrame.minY)
			case .bottomLeft:
				return CGPoint(x: cropFrame.minX, y: cropFrame.maxY)
			case .bottomRight:
				return CGPoint(x: cropFrame.maxX, y: cropFrame.maxY)
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

		private func updateCropRect(
			dragTranslation: CGSize,
			endDrag: Bool
		) {
			let translation = CGSize(
				width: dragTranslation.width - currentDrag.width,
				height: dragTranslation.height - currentDrag.height
			)
			currentDrag = endDrag ? .zero : dragTranslation

			let dx = translation.width / frame.width
			let dy = translation.height / frame.height


			if position == .center {
				cropRect.x += dx
				cropRect.y += dy
			} else {
				switch dragMode {
				case .normal:
					applyNormal(dx: dx, dy: dy)
				case .symmetric:
					applySymmetric(dx: dx, dy: dy)
				case .scale:
					applyScale(dx: dx, dy: dy)
				}
			}

			cropRect.x = max(0, min(cropRect.x, 1 - cropRect.width))
			cropRect.y = max(0, min(cropRect.y, 1 - cropRect.height))
			cropRect.width = max(0, min(cropRect.width, 1 - cropRect.x))
			cropRect.height = max(0, min(cropRect.height, 1 - cropRect.y))
		}

		private func applyNormal(dx: Double, dy: Double) {
			switch position {
			case .topLeft:
				cropRect.x += dx
				cropRect.y += dy
				cropRect.width -= dx
				cropRect.height -= dy
			case .topRight:
				cropRect.width += dx
				cropRect.y += dy
				cropRect.height -= dy
			case .bottomLeft:
				cropRect.x += dx
				cropRect.width -= dx
				cropRect.height += dy
			case .bottomRight:
				cropRect.width += dx
				cropRect.height += dy
			case .top:
				cropRect.y += dy
				cropRect.height -= dy
			case .left:
				cropRect.x += dx
				cropRect.width -= dx
			case .right:
				cropRect.width += dx
			case .bottom:
				cropRect.height += dy
			case .center:
				break
			}
		}

		private func applySymmetric( dx: Double, dy: Double) {
			switch position {
			case .topLeft:
				cropRect.x += dx
				cropRect.y += dy
				cropRect.width -= 2 * dx
				cropRect.height -= 2 * dy
			case .topRight:
				cropRect.y += dy
				cropRect.width += 2 * dx
				cropRect.height -= 2 * dy
				cropRect.x -= dx
			case .bottomLeft:
				cropRect.x += dx
				cropRect.width -= 2 * dx
				cropRect.height += 2 * dy
				cropRect.y -= dy
			case .bottomRight:
				cropRect.width += 2 * dx
				cropRect.height += 2 * dy
				cropRect.x -= dx
				cropRect.y -= dy
			case .top:
				cropRect.y += dy
				cropRect.height -= 2 * dy
			case .left:
				cropRect.x += dx
				cropRect.width -= 2 * dx
			case .right:
				cropRect.width += 2 * dx
				cropRect.x -= dx
			case .bottom:
				cropRect.height += 2 * dy
				cropRect.y -= dy
			case .center:
				break
			}
		}
		private func applyScale( dx: Double, dy: Double) {
			let oldWidth = cropRect.width, oldHeight = cropRect.height
			let centerX = cropRect.x + oldWidth / 2
			let centerY = cropRect.y + oldHeight / 2
			let scale: Double
			switch position {
			case .center:
				return
			case .topLeft:
				scale = ((1 - 2 * dx / oldWidth) + (1 - 2 * dy / oldHeight)) / 2
			case .topRight:
				scale = ((1 + 2 * dx / oldWidth) + (1 - 2 * dy / oldHeight)) / 2
			case .bottomLeft:
				scale = ((1 - 2 * dx / oldWidth) + (1 + 2 * dy / oldHeight)) / 2
			case .bottomRight:
				scale = ((1 + 2 * dx / oldWidth) + (1 + 2 * dy / oldHeight)) / 2
			case .top:
				scale = 1 - 2 * dy / oldHeight
			case .left:
				scale = 1 - 2 * dx / oldWidth
			case .right:
				scale = 1 + 2 * dx / oldWidth
			case .bottom:
				scale = 1 + 2 * dy / oldHeight
			}
			cropRect.width = oldWidth * scale
			cropRect.height = oldHeight * scale
			cropRect.x = centerX - cropRect.width / 2
			cropRect.y = centerY - cropRect.height / 2
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
