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
		let minimumSize = originalSize.aspectFill(to: 5)
		return minimumSize.width.clamped(to: ...originalSize.width).rounded()...originalSize.width
	}

	var heightMinMax: ClosedRange<Double> {
		let minimumSize = originalSize.aspectFill(to: 5)
		return minimumSize.height.clamped(to: ...originalSize.height).rounded()...originalSize.height
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
			print("ORIGINAL", originalSize, originalValue)
			guard originalSize.width != .zero else {
				return self
			}

			let newHeight = originalSize.height * (width / originalSize.width)
			return .pixels(CGSize(width: width, height: newHeight).rounded(), originalSize: originalSize)
		case .percent(_, let originalSize):
			print("ORIGINAL2", originalSize)
			let newPercent = width / originalSize.width
			return .percent(newPercent, originalSize: originalSize)
		}
	}

	func aspectResized(usingHeight height: Double) -> Self {
		switch self {
		case .pixels(_, let originalSize):
			guard originalSize.height != .zero else {
				return self
			}

			let newWidth = originalSize.width * (height / originalSize.height)
			return .pixels(CGSize(width: newWidth, height: height).rounded(), originalSize: originalSize)
		case .percent(_, let originalSize):
			let newPercent = height / originalSize.height
			return .percent(newPercent, originalSize: originalSize)
		}
	}
}
