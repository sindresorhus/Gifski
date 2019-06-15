import struct CoreGraphics.CGSize
import struct CoreGraphics.CGFloat

enum DimensionsType: Equatable, CaseIterable {
	case pixels
	case percent

	var title: String {
		switch self {
		case .pixels:
			return "pixels"
		case .percent:
			return "percent"
		}
	}
}

struct Dimensions: Equatable {
	let type: DimensionsType
	let dimensions: CGSize
}

final class ResizableDimensions {

	var dimensions: Dimensions

	/// Minimum scaling, 1.0 being the original size
	var minimumScale: CGFloat

	/// Maximum scaling, 1.0 being the original size
	var maximumScale: CGFloat

	private let originalDimensions: Dimensions
	private var currentScale: CGFloat

	init(dimensions: Dimensions, minimumScale: CGFloat? = nil, maximumScale: CGFloat? = nil) {
		self.originalDimensions = dimensions
		self.dimensions = dimensions
		self.minimumScale = minimumScale ?? 0.01
		self.maximumScale = maximumScale ?? 1.0
		self.currentScale = 1.0
	}

	func change(dimensionsType: DimensionsType) -> Dimensions {
		dimensions = calculateDimensions(for: dimensionsType)

		return dimensions
	}

	func resize(to newDimensions: CGSize) -> Dimensions {
		let newScale = calculateScale(for: newDimensions)
		currentScale = validated(scale: newScale)
		dimensions = calculateDimensions(for: dimensions.type)

		return dimensions
	}

	func validate(newSize: CGSize) -> Bool {
		let scale = calculateScale(for: newSize)
		return validated(scale: scale) == scale
	}

	private func calculateDimensions(for type: DimensionsType) -> Dimensions {
		let multiplier: CGSize = {
			switch type {
			case .percent:
				return CGSize(width: 100.0, height: 100.0)
			case .pixels:
				return originalDimensions.dimensions
			}
		}()

		let width = currentScale * multiplier.width
		let height = currentScale * multiplier.height

		return Dimensions(type: type, dimensions: CGSize(width: width, height: height))
	}

	private func calculateScale(for newDimensions: CGSize) -> CGFloat {
		return (currentScale * newDimensions.width) / dimensions.dimensions.width
	}

	private func validated(scale: CGFloat) -> CGFloat {
		return scale.clamped(to: minimumScale...maximumScale)
	}
}

extension ResizableDimensions: CustomStringConvertible {

	var description: String {
		switch dimensions.type {
		case .percent:
			let pixels = calculateDimensions(for: .pixels)
			return String(format: "%.0f%% (%.0fx%.0f)", dimensions.dimensions.width, pixels.dimensions.width, pixels.dimensions.height)
		case .pixels:
			let percent = calculateDimensions(for: .percent)
			return String(format: "%.0fx%.0f (%.0f%%)", dimensions.dimensions.width, dimensions.dimensions.height, percent.dimensions.width)
		}
	}
}
