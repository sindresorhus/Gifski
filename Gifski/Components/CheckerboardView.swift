import SwiftUI

struct CheckerboardView: View {
	static let gridSize = 8
	/// I tried just using firstColor directly (instead of splitting between light and dark), but it would not reliably change colors for the preview when switching between light and dark
	static let firstColorLight = Color(white: 0.98)
	static let firstColorDark = Color(white: 0.46)
	static let secondColorLight = Color(white: 0.82)
	static let secondColorDark = Color(white: 0.26)

	var gridSize = CGSize(width: Self.gridSize, height: Self.gridSize)
	static var firstColor = Color(light: firstColorLight, dark: firstColorDark)
	static var secondColor = Color(light: secondColorLight, dark: secondColorDark)
	var clearRect: CGRect?

	var body: some View {
		ZStack {
			Canvas(opaque: true) { context, size in
				context.fill(Rectangle().path(in: size.cgRect), with: .color(Self.secondColor))

				for y in 0...Int(size.height / gridSize.height) {
					for x in 0...Int(size.width / gridSize.width) where x.isEven == y.isEven {
						let origin = CGPoint(x: x * Int(gridSize.width), y: y * Int(gridSize.height))
						let rect = CGRect(origin: origin, size: gridSize)
						context.fill(Rectangle().path(in: rect), with: .color(Self.firstColor))
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
