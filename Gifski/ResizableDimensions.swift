import struct CoreGraphics.CGSize
import struct CoreGraphics.CGFloat

enum DimensionsType: String, Equatable, CaseIterable {
	case pixels
	case percent
}

struct Dimensions: Equatable, CustomStringConvertible {
	let type: DimensionsType
	let value: CGSize

	func rounded(_ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Self {
		Self(type: type, value: value.rounded(rule))
	}

	var description: String {
		switch type {
		case .pixels:
			return String(format: "%.0f × %.0f", value.width, value.height)
		case .percent:
			return String(format: "%.0f%%", value.width)
		}
	}
}

final class ResizableDimensions: Copyable {
	/// Minimum scaling, 1.0 being the original size.
	let minimumScale: CGFloat

	/// Maximum scaling, 1.0 being the original size.
	let maximumScale: CGFloat

	/// Width bounds for `currentDimensions`.
	var widthMinMax: ClosedRange<CGFloat> {
		let multiplier = multiplier(for: currentDimensions.type)
		let min = (minimumScale * multiplier.width).rounded()
		let max = (maximumScale * multiplier.width).rounded()
		return min...max
	}

	/// Height bounds for `currentDimensions`.
	var heightMinMax: ClosedRange<CGFloat> {
		let multiplier = multiplier(for: currentDimensions.type)
		let min = (minimumScale * multiplier.height).rounded()
		let max = (maximumScale * multiplier.height).rounded()
		return min...max
	}

	private(set) var currentDimensions: Dimensions
	private let originalDimensions: Dimensions
	private var currentScale: CGFloat

	init(
		dimensions: Dimensions,
		minimumScale: CGFloat? = nil,
		maximumScale: CGFloat? = nil
	) {
		self.originalDimensions = dimensions.rounded()
		self.currentDimensions = originalDimensions
		self.minimumScale = minimumScale ?? 0.01
		self.maximumScale = maximumScale ?? 1
		self.currentScale = 1
	}

	init(instance: ResizableDimensions) {
		self.originalDimensions = instance.originalDimensions
		self.minimumScale = instance.minimumScale
		self.maximumScale = instance.maximumScale
		self.currentScale = instance.currentScale
		self.currentDimensions = instance.currentDimensions
	}

	func change(dimensionsType: DimensionsType) {
		currentDimensions = calculateDimensions(for: dimensionsType)
	}

	func changed(dimensionsType: DimensionsType) -> Self {
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
		return scalesEqual(validated(scale: scale), scale)
	}

	private func scalesEqual(_ scale1: CGFloat, _ scale2: CGFloat) -> Bool {
		scale1.isAlmostEqual(to: scale2, tolerance: 0.001)
	}

	private func calculateDimensions(for type: DimensionsType) -> Dimensions {
		let multiplier = multiplier(for: type)
		let width = currentScale * multiplier.width
		let height = currentScale * multiplier.height

		let dimensions = Dimensions(type: type, value: CGSize(width: width, height: height))
		return type == .pixels ? dimensions.rounded() : dimensions.rounded(.down)
	}

	private func calculateScale(usingWidth width: CGFloat) -> CGFloat {
		width / multiplier(for: currentDimensions.type).width
	}

	private func calculateScale(usingHeight height: CGFloat) -> CGFloat {
		height / multiplier(for: currentDimensions.type).height
	}

	private func validated(scale: CGFloat) -> CGFloat {
		scale.clamped(to: minimumScale...maximumScale)
	}

	private func multiplier(for type: DimensionsType) -> CGSize {
		switch type {
		case .percent:
			return CGSize(width: 100, height: 100)
		case .pixels:
			return originalDimensions.value
		}
	}
}

extension ResizableDimensions: CustomStringConvertible {
	var description: String {
		switch currentDimensions.type {
		case .percent:
			let pixelsDimensions = changed(dimensionsType: .pixels).currentDimensions
			return "\(currentDimensions) (\(pixelsDimensions == originalDimensions ? "Original" : "\(pixelsDimensions)"))"
		case .pixels:
			let percentDimensions = changed(dimensionsType: .percent).currentDimensions
			return "\(currentDimensions) (\(currentDimensions == originalDimensions ? "Original" : "~\(percentDimensions)"))"
		}
	}
}
