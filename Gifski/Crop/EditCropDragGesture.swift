//
//  EditCropDragGesture.swift
//  Gifski
//
//  Created by Michael Mulet on 4/27/25.
//

import Foundation
import SwiftUI

struct EditCropDragGesture: ViewModifier {
	@Binding var isDragging: Bool
	@Binding var cropRect: CropRect
	var frame: CGRect
	var position: CropHandlePosition
	var dragMode: CropRect.DragMode

	@State private var beginDragCropRect: CropRect?

	func body(content: Content) -> some View {
		content
			.highPriorityGesture(
				DragGesture()
					.onChanged { drag in
						isDragging = true
						beginDragCropRect = beginDragCropRect ?? cropRect
						cropRect = beginDragCropRect?.applyDragToCropRect(
							drag: drag,
							frame: frame,
							position: position,
							dragMode: dragMode
						) ?? cropRect
					}
					.onEnded { drag in
						isDragging = false
						cropRect = beginDragCropRect?.applyDragToCropRect(
							drag: drag,
							frame: frame,
							position: position,
							dragMode: dragMode
						) ?? cropRect

						beginDragCropRect = nil
					}
			)
	}
}

extension View {
	func editCropDragGesture(
		isDragging: Binding<Bool>,
		cropRect: Binding<CropRect>,
		frame: CGRect,
		position: CropHandlePosition,
		dragMode: CropRect.DragMode
	) -> some View {
		modifier(EditCropDragGesture(
			isDragging: isDragging,
			cropRect: cropRect,
			frame: frame,
			position: position,
			dragMode: dragMode
		))
	}
}
