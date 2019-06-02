import struct CoreGraphics.CGSize

enum DimensionsMode: CaseIterable {
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

	var deltaUnit: Int {
		return 1
	}

	var biggerDeltaUnit: Int {
		return 10
	}

	init(title: String) {
		switch title {
		case DimensionsMode.percent.title:
			self = .percent
		default:
			self = .pixels
		}
	}

	func width(fromScale scale: Double, originalSize: CGSize) -> Double {
		switch self {
		case .pixels:
			return Double(originalSize.width) * scale
		case .percent:
			return 100.0 * scale
		}
	}

	func height(fromScale scale: Double, originalSize: CGSize) -> Double {
		switch self {
		case .pixels:
			return Double(originalSize.height) * scale
		case .percent:
			return 100.0 * scale
		}
	}

	func scale(width: Double, originalSize: CGSize) -> Double {
		switch self {
		case .pixels:
			return width / Double(originalSize.width)
		case .percent:
			return width / 100.0
		}
	}

	func scale(height: Double, originalSize: CGSize) -> Double {
		switch self {
		case .pixels:
			return height / Double(originalSize.height)
		case .percent:
			return height / 100.0
		}
	}

	func validated(widthScale: Double, originalSize: CGSize) -> Double {
		let range = self == .pixels ? (1.0...Double(originalSize.width)) : (1.0...100.0)
		let maxValue = self == .pixels ? Double(originalSize.width) : 100.0
		return validated(scale: widthScale, maxValue: maxValue, range: range)
	}

	func validated(heightScale: Double, originalSize: CGSize) -> Double {
		let range = self == .pixels ? (1.0...Double(originalSize.height)) : (1.0...100.0)
		let maxValue = self == .pixels ? Double(originalSize.height) : 100.0
		return validated(scale: heightScale, maxValue: maxValue, range: range)
	}

	private func validated(scale: Double, maxValue: Double, range: ClosedRange<Double>) -> Double {
		let scaledValue = scale * maxValue
		let validatedScaledValue = scaledValue.clamped(to: range)
		return validatedScaledValue / maxValue
	}
}
