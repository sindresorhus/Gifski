import CoreGraphics
import AppIntents

enum DimensionsType: String, Equatable, CaseIterable {
	case pixels
	case percent
}

extension DimensionsType: AppEnum {
	static let typeDisplayRepresentation: TypeDisplayRepresentation = "Dimension Type"

	static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
		.pixels: "Pixels",
		.percent: "Percent"
	]
}

enum Dimensions: Hashable {
	case pixels(_ value: CGSize, originalSize: CGSize)
	case percent(_ value: Double, originalSize: CGSize)
}

extension Dimensions {
	var pixels: CGSize {
		switch self {
		case .pixels(let value, _):
			return value.rounded()
		case .percent(let percent, let originalSize):
			guard originalSize != .zero else {
				return .zero
			}

			return (originalSize * percent).rounded()
		}
	}

	var percent: Double {
		switch self {
		case .pixels(let value, let originalSize):
			guard originalSize.width > 0 else {
				return 0
			}

			return value.width / originalSize.width
		case .percent(let value, _):
			return value
		}
	}

	var isPercent: Bool {
		switch self {
		case .pixels:
			false
		case .percent:
			true
		}
	}

	var originalSize: CGSize {
		switch self {
		case .pixels(_, let originalSize):
			originalSize
		case .percent(_, let originalSize):
			originalSize
		}
	}

	var widthMinMax: ClosedRange<Double> {
		.fromGraceful(10, originalSize.width)
	}

	var heightMinMax: ClosedRange<Double> {
		.fromGraceful(10, originalSize.height)
	}

	var percentMinMax: ClosedRange<Double> { 1...100 }

	func rounded(_ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Self {
		switch self {
		case .pixels(let value, let originalSize):
			let roundedValue = CGSize(width: value.width.rounded(rule), height: value.height.rounded(rule))
			return .pixels(roundedValue, originalSize: originalSize)
		case .percent(let value, let originalSize):
			let roundedValue = value.rounded(rule)
			return .percent(roundedValue, originalSize: originalSize)
		}
	}

	func resized(to newSize: CGSize) -> Self {
		switch self {
		case .pixels(_, let originalSize):
			return .pixels(newSize, originalSize: originalSize)
		case .percent(_, let originalSize):
			let newWidthPercent = (newSize.width / originalSize.width) * 100
			let newHeightPercent = (newSize.height / originalSize.height) * 100
			let averagePercent = (newWidthPercent + newHeightPercent) / 2
			return .percent(averagePercent, originalSize: originalSize)
		}
	}
}

extension Dimensions: CustomStringConvertible {
	var description: String {
		switch self {
		case .pixels(let value, _):
			let percent = percent * 100
			let percentString = percent == 100 ? "Original" : String(format: "~%.0f%%", percent)
			return "\(value.formatted) (\(percentString))"
		case .percent(let value, _):
			let pixels = pixels
			let percentValue = value * 100
			let pixelString = percentValue == 100 ? "Original" : "\(pixels.formatted)"
			return String(format: "%.0f%% (\(pixelString))", percentValue)
		}
	}
}

extension Dimensions {
	func aspectResized(usingWidth width: Double) -> Self {
		switch self {
		case .pixels(let originalValue, let originalSize):
			guard originalValue.width != .zero else {
				return self
			}

			let newHeight = originalValue.height * (width / originalValue.width)
			return .pixels(CGSize(width: width, height: newHeight).rounded(), originalSize: originalSize)
		case .percent(_, let originalSize):
			let newPercent = width / originalSize.width
			return .percent(newPercent, originalSize: originalSize)
		}
	}

	func aspectResized(usingHeight height: Double) -> Self {
		switch self {
		case .pixels(let originalValue, let originalSize):
			guard originalValue.height != .zero else {
				return self
			}

			let newWidth = originalValue.width * (height / originalValue.height)
			return .pixels(CGSize(width: newWidth, height: height).rounded(), originalSize: originalSize)
		case .percent(_, let originalSize):
			let newPercent = height / originalSize.height
			return .percent(newPercent, originalSize: originalSize)
		}
	}
}




//final class ResizableDimensions: Copyable, ReflectiveHashable {
//	/**
//	Minimum scaling, 1.0 being the original size.
//	*/
//	let minimumScale: Double
//
//	/**
//	Maximum scaling, 1.0 being the original size.
//	*/
//	let maximumScale: Double
//
//	/**
//	Width bounds for `currentDimensions`.
//	*/
//	var widthMinMax: ClosedRange<Double> {
//		let multiplier = multiplier(for: currentDimensions.type)
//		let min = (minimumScale * multiplier.width).rounded()
//		let max = (maximumScale * multiplier.width).rounded()
//		return min...max
//	}
//
//	/**
//	Height bounds for `currentDimensions`.
//	*/
//	var heightMinMax: ClosedRange<Double> {
//		let multiplier = multiplier(for: currentDimensions.type)
//		let min = (minimumScale * multiplier.height).rounded()
//		let max = (maximumScale * multiplier.height).rounded()
//		return min...max
//	}
//
//	private(set) var currentDimensions: Dimensions
//	private let originalDimensions: Dimensions
//	private var currentScale: Double
//
//	init(
//		dimensions: Dimensions,
//		minimumScale: Double? = nil,
//		maximumScale: Double? = nil
//	) {
//		self.originalDimensions = dimensions.rounded()
//		self.currentDimensions = originalDimensions
//		self.minimumScale = minimumScale ?? 0.01
//		self.maximumScale = maximumScale ?? 1
//		self.currentScale = 1
//	}
//
//	init(instance: ResizableDimensions) {
//		self.originalDimensions = instance.originalDimensions
//		self.minimumScale = instance.minimumScale
//		self.maximumScale = instance.maximumScale
//		self.currentScale = instance.currentScale
//		self.currentDimensions = instance.currentDimensions
//	}
//
//	func change(dimensionsType: DimensionsType) {
//		currentDimensions = calculateDimensions(for: dimensionsType)
//	}
//
//	func changed(dimensionsType: DimensionsType) -> Self {
//		let resizableDimensions = copy()
//		resizableDimensions.change(dimensionsType: dimensionsType)
//		return resizableDimensions
//	}
//
//	func resize(to newDimensions: CGSize) {
//		let newScale = calculateScale(usingWidth: newDimensions.width)
//		currentScale = validated(scale: newScale)
//		currentDimensions = calculateDimensions(for: currentDimensions.type)
//	}
//
//	func resize(usingWidth width: Double) {
//		let newScale = calculateScale(usingWidth: width)
//		currentScale = validated(scale: newScale)
//		currentDimensions = calculateDimensions(for: currentDimensions.type)
//	}
//
//	func resize(usingHeight height: Double) {
//		let newScale = calculateScale(usingHeight: height)
//		currentScale = validated(scale: newScale)
//		currentDimensions = calculateDimensions(for: currentDimensions.type)
//	}
//
//	func resized(to newDimensions: CGSize) -> ResizableDimensions {
//		let resizableDimensions = copy()
//		resizableDimensions.resize(to: newDimensions)
//		return resizableDimensions
//	}
//
//	func validate(newSize: CGSize) -> Bool {
//		let scale = calculateScale(usingWidth: newSize.width)
//		return scalesEqual(validated(scale: scale), scale)
//	}
//
//	private func scalesEqual(_ scale1: Double, _ scale2: Double) -> Bool {
//		scale1.isAlmostEqual(to: scale2, tolerance: 0.001)
//	}
//
//	private func calculateDimensions(for type: DimensionsType) -> Dimensions {
//		let multiplier = multiplier(for: type)
//		let width = currentScale * multiplier.width
//		let height = currentScale * multiplier.height
//
//		let dimensions = Dimensions(type: type, value: CGSize(width: width, height: height))
//		return type == .pixels ? dimensions.rounded() : dimensions.rounded(.down)
//	}
//
//	private func calculateScale(usingWidth width: Double) -> Double {
//		width / multiplier(for: currentDimensions.type).width
//	}
//
//	private func calculateScale(usingHeight height: Double) -> Double {
//		height / multiplier(for: currentDimensions.type).height
//	}
//
//	private func validated(scale: Double) -> Double {
//		scale.clamped(to: minimumScale...maximumScale)
//	}
//
//	private func multiplier(for type: DimensionsType) -> CGSize {
//		switch type {
//		case .percent:
//			CGSize(width: 100, height: 100)
//		case .pixels:
//			originalDimensions.value
//		}
//	}
//}
//
//extension ResizableDimensions: CustomStringConvertible {
//	var description: String {
//		switch currentDimensions.type {
//		case .percent:
//			let pixelsDimensions = changed(dimensionsType: .pixels).currentDimensions
//			return "\(currentDimensions) (\(pixelsDimensions == originalDimensions ? "Original" : "\(pixelsDimensions)"))"
//		case .pixels:
//			let percentDimensions = changed(dimensionsType: .percent).currentDimensions
//			return "\(currentDimensions) (\(currentDimensions == originalDimensions ? "Original" : "~\(percentDimensions)"))"
//		}
//	}
//}
