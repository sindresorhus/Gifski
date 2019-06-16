import struct CoreGraphics.CGSize
import struct CoreGraphics.CGFloat

enum DimensionsType: String, Equatable, CaseIterable {
	case pixels
	case percent
}

struct Dimensions: Equatable {
	let type: DimensionsType
	let value: CGSize
}

final class ResizableDimensions {
	/// Minimum scaling, 1.0 being the original size
	let minimumScale: CGFloat

	/// Maximum scaling, 1.0 being the original size
	let maximumScale: CGFloat

	private(set) var currentDimensions: Dimensions
	private let originalDimensions: Dimensions
	private var currentScale: CGFloat

	init(dimensions: Dimensions, minimumScale: CGFloat? = nil, maximumScale: CGFloat? = nil) {
		self.originalDimensions = dimensions
		self.currentDimensions = dimensions
		self.minimumScale = minimumScale ?? 0.01
		self.maximumScale = maximumScale ?? 1.0
		self.currentScale = 1.0
	}

	private func copy() -> ResizableDimensions {
		let resizableDimensions = ResizableDimensions(dimensions: originalDimensions, minimumScale: minimumScale, maximumScale: maximumScale)
		resizableDimensions.currentDimensions = currentDimensions
		resizableDimensions.currentScale = currentScale

		return resizableDimensions
	}

	func change(dimensionsType: DimensionsType) {
		currentDimensions = calculateDimensions(for: dimensionsType)
	}

	func changed(dimensionsType: DimensionsType) -> ResizableDimensions {
		let resizableDimensions = copy()
		resizableDimensions.change(dimensionsType: dimensionsType)

		return resizableDimensions
	}

	func resize(to newDimensions: CGSize) {
		let newScale = calculateScale(usingWidth: newDimensions.width)
		currentScale = validated(scale: newScale)
		currentDimensions = calculateDimensions(for: currentDimensions.type)
	}

	func resize(usingWidth width: CGFloat) {
		let newScale = calculateScale(usingWidth: width)
		currentScale = validated(scale: newScale)
		currentDimensions = calculateDimensions(for: currentDimensions.type)
	}

	func resize(usingHeight height: CGFloat) {
		let newScale = calculateScale(usingHeight: height)
		currentScale = validated(scale: newScale)
		currentDimensions = calculateDimensions(for: currentDimensions.type)
	}

	func resized(to newDimensions: CGSize) -> ResizableDimensions {
		let resizableDimensions = copy()
		resizableDimensions.resize(to: newDimensions)

		return resizableDimensions
	}

	func validate(newSize: CGSize) -> Bool {
		let scale = calculateScale(usingWidth: newSize.width)
		return validated(scale: scale) == scale
	}

	func validate(newWidth width: CGFloat) -> Bool {
		let scale = calculateScale(usingWidth: width)
		return validated(scale: scale) == scale
	}

	func validate(newHeight height: CGFloat) -> Bool {
		let scale = calculateScale(usingHeight: height)
		return validated(scale: scale) == scale
	}

	private func calculateDimensions(for type: DimensionsType) -> Dimensions {
		let multiplier: CGSize = {
			switch type {
			case .percent:
				return CGSize(width: 100.0, height: 100.0)
			case .pixels:
				return originalDimensions.value
			}
		}()

		let width = currentScale * multiplier.width
		let height = currentScale * multiplier.height

		return Dimensions(type: type, value: CGSize(width: width, height: height))
	}

	private func calculateScale(usingWidth width: CGFloat) -> CGFloat {
		return (currentScale * width) / currentDimensions.value.width
	}

	private func calculateScale(usingHeight height: CGFloat) -> CGFloat {
		return (currentScale * height) / currentDimensions.value.height
	}

	private func validated(scale: CGFloat) -> CGFloat {
		return scale.clamped(to: minimumScale...maximumScale)
	}
}

extension ResizableDimensions: CustomStringConvertible {
	var description: String {
		switch currentDimensions.type {
		case .percent:
			let pixels = changed(dimensionsType: .pixels).pixelsDescription
			let percent = percentDescription
			return "\(percent) (\(currentScale == 1.0 ? "Original" : pixels))"
		case .pixels:
			let percent = changed(dimensionsType: .percent).percentDescription
			let pixels = pixelsDescription
			return "\(pixels) (\(currentScale == 1.0 ? "Original" : percent))"
		}
	}

	private var pixelsDescription: String {
		return String(format: "%.0f x %.0f", currentDimensions.value.width, currentDimensions.value.height)
	}

	private var percentDescription: String {
		return String(format: "%.0f%%", currentDimensions.value.width)
	}
}
