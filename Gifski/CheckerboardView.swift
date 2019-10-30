import Cocoa

final class CheckerboardView: NSView {
	private let gridSize = CGSize(width: 8, height: 8)
	private let clearRect: CGRect

	init(frame: CGRect, clearRect: CGRect) {
		self.clearRect = clearRect

		super.init(frame: frame)
	}

	required init?(coder: NSCoder) {
		self.clearRect = .zero

		super.init(coder: coder)
	}

	override func draw(_ dirtyRect: CGRect) {
		super.draw(dirtyRect)

		NSColor.Checkerboard.first.setFill()
		dirtyRect.fill()

		NSColor.Checkerboard.second.setFill()

		for y in 0...Int(bounds.size.height / gridSize.height) {
			for x in 0...Int(bounds.size.width / gridSize.width) where x.isEven == y.isEven {
				let origin = CGPoint(x: x * Int(gridSize.width), y: y * Int(gridSize.height))
				let rect = CGRect(origin: origin, size: gridSize)
				rect.fill()
			}
		}

		clearRect.fill(using: .clear)
	}
}
