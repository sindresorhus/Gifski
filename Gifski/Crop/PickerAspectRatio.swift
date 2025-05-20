import Foundation

struct PickerAspectRatio: Hashable {
	var width: Int
	var height: Int

	init(_ width: Int, _ height: Int) {
		self.width = width
		self.height = height
	}
}

extension PickerAspectRatio: CustomStringConvertible {
	var description: String {
		"\(width):\(height)"
	}
}

extension PickerAspectRatio {
	static let presets: [Self] = [
		.init(16, 9),
		.init(4, 3),
		.init(1, 1),
		.init(9, 16),
		.init(3, 4)
	]

	/**
	The description is the aspect ratio and the size in pixels for the given crop rect if were to switch to using this aspect ratio.
	*/
	func description(
		forVideoDimensions dimensions: CGSize,
		cropRect: CropRect
	) -> String {
		"\(description) - \(cropRect.withAspectRatio(for: self, forDimensions: dimensions).unnormalize(forDimensions: dimensions).size.videoSizeDescription)"
	}

	var aspectRatio: Double {
		Double(width) / Double(height)
	}
}

extension PickerAspectRatio {
	func matchesPreset() -> Bool {
		Self.presets.contains { $0.isCloseTo(self.aspectRatio) }
	}

	func isCloseTo(_ aspect: Double, tolerance: Double = 0.01) -> Bool {
		abs(aspectRatio - aspect) < tolerance
	}

	static func selectionText(
		for aspect: Double,
		customAspectRatio: PickerAspectRatio?,
		videoDimensions: CGSize,
		cropRect: CropRect
	) -> String {
		let allRatios = presets + (customAspectRatio.map { [$0] } ?? [])

		if let matchingRatio = allRatios.first(where: { $0.aspectRatio.isAlmostEqual(to: aspect) }) {
			return matchingRatio.description(
				forVideoDimensions: videoDimensions,
				cropRect: cropRect
			)
		}

		let customSizeDescription = cropRect.unnormalize(forDimensions: videoDimensions).size.videoSizeDescription

		return "Custom - \(customSizeDescription)"
	}


	/**
	Calculates the closest current aspect ratio of the crop rec with width and height within the given range.

	First, it tries to calculate the greatest common divisor (GCD) of the width and height to simplify the ratio. If the the width and height of the ratio are both less than within the range, it uses that as the aspect ratio. Otherwise, it approximates the aspect ratio by finding the closest fraction with a denominator less than the upper bound of the range that matches the current aspect ratio as closely as possible.
	*/
	static func closestAspectRatio(
		for size: CGSize,
		within range: ClosedRange<Int>
	) -> Self {
		let (intWidth, intHeight) = size.integerAspectRatio()

		if
			range.contains(intWidth),
			range.contains(intHeight)
		{
			return .init(intWidth, intHeight)
		}

		return approximateAspectRatio(for: size, within: range)
	}

	private static func approximateAspectRatio(
		for size: CGSize,
		within range: ClosedRange<Int>
	) -> Self {
		// Calculate the aspect ratio as a floating-point value
		let aspect = size.width / size.height

		// Generate all possible numerator-denominator pairs within the range
		let bestPairMap = range.flatMap { denominator in
			let numerator = Int(round(aspect * Double(denominator)))
			return range.contains(numerator) ? [(numerator, denominator)] : []
		}

		// Find the pair that most closely matches the aspect ratio
		let bestPair = bestPairMap.min {
			abs(Double($0.0) / Double($0.1) - aspect) < abs(Double($1.0) / Double($1.1) - aspect)
		} ?? (1, 1)

		return .init(bestPair.0, bestPair.1)
	}
}

extension CropRect {
	func withAspectRatio(
		for newRatio: PickerAspectRatio,
		forDimensions dimensions: CGSize
	) -> CropRect {
		withAspectRatio(
			aspectWidth: Double(newRatio.width),
			aspectHeight: Double(newRatio.height),
			forDimensions: dimensions
		)
	}
}
