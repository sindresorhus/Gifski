import SwiftUI

struct CheckerboardView: View {
	var gridSize = CGSize(width: 8, height: 8)
	var firstColor = Color(light: .init(white: 0.98), dark: .init(white: 0.46))
	var secondColor = Color(light: .init(white: 0.82), dark: .init(white: 0.26))
	var clearRect: CGRect?

	var body: some View {
		ZStack {
			Canvas(opaque: true) { context, size in
				context.fill(Rectangle().path(in: size.cgRect), with: .color(secondColor))

				for y in 0...Int(size.height / gridSize.height) {
					for x in 0...Int(size.width / gridSize.width) where x.isEven == y.isEven {
						let origin = CGPoint(x: x * Int(gridSize.width), y: y * Int(gridSize.height))
						let rect = CGRect(origin: origin, size: gridSize)
						context.fill(Rectangle().path(in: rect), with: .color(firstColor))
					}
				}
			}
			// TODO: Any way to do this directly in the `Canvas`?
			if let clearRect {
				Rectangle()
					.fill(.black)
					.frame(width: clearRect.width, height: clearRect.height)
					.blendMode(.destinationOut)
			}
		}
		.compositingGroup()
		.drawingGroup()
	}
}
