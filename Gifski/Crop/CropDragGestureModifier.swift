import SwiftUI

extension View {
	func cropDragGesture(
		isDragging: Binding<Bool>,
		cropRect: Binding<CropRect>,
		frame: CGRect,
		dimensions: CGSize,
		position: CropHandlePosition,
		dragMode: CropRect.DragMode
	) -> some View {
		modifier(
			CropDragGestureModifier(
				isDragging: isDragging,
				cropRect: cropRect,
				frame: frame,
				dimensions: dimensions,
				position: position,
				dragMode: dragMode
			)
		)
	}
}

private struct CropDragGestureModifier: ViewModifier {
	@GestureState private var initialCropRect: CropRect?

	@Binding var isDragging: Bool
	@Binding var cropRect: CropRect
	let frame: CGRect
	let dimensions: CGSize
	let position: CropHandlePosition
	let dragMode: CropRect.DragMode

	func body(content: Content) -> some View {
		let dragGesture = DragGesture()
			.updating($initialCropRect) { _, state, _ in
				state = state ?? cropRect
			}
			.onChanged { drag in
				guard let initial = initialCropRect else {
					return
				}

				isDragging = true

				cropRect = initial.applyDragToCropRect(
					drag: drag,
					frame: frame,
					dimensions: dimensions,
					position: position,
					dragMode: dragMode
				)
			}
			.onEnded { _ in
				isDragging = false
			}
		content.highPriorityGesture(dragGesture)
	}
}
