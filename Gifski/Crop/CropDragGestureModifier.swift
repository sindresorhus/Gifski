//
//  EditCropDragGesture.swift
//  Gifski
//
//  Created by Michael Mulet on 4/27/25.
//

import Foundation
import SwiftUI

private struct CropDragGestureModifier: ViewModifier {
	@Binding var isDragging: Bool
	@Binding var cropRect: CropRect
	let frame: CGRect
	let position: CropHandlePosition
	let dragMode: CropRect.DragMode

	@GestureState private var initialCropRect: CropRect?

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

extension View {
	func cropDragGesture(
		isDragging: Binding<Bool>,
		cropRect: Binding<CropRect>,
		frame: CGRect,
		position: CropHandlePosition,
		dragMode: CropRect.DragMode
	) -> some View {
		modifier(CropDragGestureModifier(
			isDragging: isDragging,
			cropRect: cropRect,
			frame: frame,
			position: position,
			dragMode: dragMode
		))
	}
}
