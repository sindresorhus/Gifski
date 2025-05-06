import AppIntents
import AVFoundation


struct CropEntity: AppEntity, Codable, Equatable, Hashable, Identifiable {
	private static let errorId = "0"
	var id: String {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		return (try? encoder.encode(self).base64EncodedString()) ?? Self.errorId
	}
	init() {
		self.mode = .aspectRatio
		self.width = 1
		self.height = 1
	}
	static var defaultQuery = CropEntityQuery()
	static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Crop")

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: "\(description)")
	}


	var mode: CropIntentMode
	var x: Int?
	var bottomLeftY: Int?
	var width: Int
	var height: Int

	var description: String {
		switch mode {
		case .exact:
			"\(width)x\(height) at (\(x ?? 0),\(bottomLeftY ?? 0))"
		case .aspectRatio:
			"\(width):\(height)"
		}
	}

	func cropRect(forDimensions dimensions: (Int, Int)) throws -> CropRect? {
		let (dimensionsWidth, dimensionsHeight) = dimensions
		switch mode {
		case .exact:
			guard let bottomLeftY,
				  let x
			else {
				return nil
			}
			let cropWidth = self.width > 1 ? self.width : 1
			let cropHeight = self.height > 1 ? self.height : 1

			let topLeftY = dimensionsHeight - bottomLeftY - cropHeight
			let entityRect = CGRect(x: x, y: topLeftY, width: cropWidth, height: cropHeight)
			let videoRect = CGRect(origin: .zero, size: .init(width: dimensionsWidth, height: dimensionsHeight))
			let intersectionRect = videoRect.intersection(entityRect)

			guard intersectionRect.width >= 1,
				  intersectionRect.height >= 1 else {
				throw CropOutOfBounds(enteredRect: CGRect(x: x, y: bottomLeftY, width: cropWidth, height: cropHeight), videoRect: videoRect)
			}
			return CropRect(
				x: Double(intersectionRect.x) / Double(dimensionsWidth),
				y: Double(intersectionRect.y) / Double(dimensionsHeight),
				width: Double(intersectionRect.width) / Double(dimensionsWidth),
				height: Double(intersectionRect.height) / Double(dimensionsHeight)
			)
		case .aspectRatio:
			let aspectWidth = self.width > 1 ? self.width : 1
			let aspectHeight = self.height > 1 ? self.height : 1
			return CropRect.centeredFrom(aspectWidth: Double(aspectWidth), aspectHeight: Double(aspectHeight), forDimensions: .init(width: dimensionsWidth, height: dimensionsHeight))
		}
	}
	static func from(id: String) throws -> Self {
		guard id != Self.errorId else {
			return Self()
		}
		guard let data = Data(base64Encoded: id) else {
			throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid ID format"))
		}
		return try JSONDecoder().decode(Self.self, from: data)
	}
}


struct CropEntityQuery: EntityQuery {
	func entities(for identifiers: [CropEntity.ID]) async throws -> [CropEntity] {
		try identifiers.map {
			try CropEntity.from(id: $0)
		}
	}
	func suggestedEntities() async throws -> [CropEntity] {
		PickerAspectRatio.presets.map {
			var crop  = CropEntity()
			crop.mode = .aspectRatio
			crop.width = $0.width
			crop.height = $0.height
			return crop
		}
	}
}

enum CropIntentMode: String, AppEnum, CaseIterable, Codable, Hashable {
	static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
		.aspectRatio: DisplayRepresentation(title: "a fixed aspect ratio"),
		.exact: DisplayRepresentation(title: "exact dimensions")
	]
	case aspectRatio
	case exact
	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Crop Mode")
}
struct CropOutOfBounds: LocalizedError, CustomNSError {
	let enteredRect: CGRect
	let videoRect: CGRect
	var errorDescription: String? {
		"Crop rectangle is out of bounds! It's \(enteredRect.width)x\(enteredRect.height) at (\(enteredRect.x),\(enteredRect.y)), but it needs to fit inside \(videoRect.width)x\(videoRect.height) for this video."
	}
	var failureReason: String? {
		"The crop rectangle is out of bounds."
	}
	var recoverySuggestion: String? {
		"Move the crop rectangle into the video bounds."
	}
	/**
	 Needed for the error description to show in shortcuts
	 */
	static var errorDomain: String { "CropOutOfBoundsError" }
	/**
	 Needed  for the error description to show in shortcuts
	 */
	var errorUserInfo: [String: Any] {
		[
			NSLocalizedDescriptionKey: errorDescription ?? "Crop rectangle is out of bounds."
		]
	}
}

struct CreateCropIntent: AppIntent {
	static var title: LocalizedStringResource = "Create Crop for Gifski"

	static let description = IntentDescription(
		"""
		Creates a crop to pass into the “Convert Video to Animated GIF” action.
		""",
		searchKeywords: [
			"video",
			"conversion",
			"converter",
			"crop",
			"mp4",
			"mov"
		],
		resultValueName: "Crop"
	)

	static var parameterSummary: some ParameterSummary {
		Switch(\.$mode) {
			Case(.exact) {
				Summary("Create a crop with \(\.$mode):  \(\.$width)x\(\.$height) at (\(\.$x), \(\.$y))")
			}
			DefaultCase {
				Summary("Create a crop with \(\.$mode):  \(\.$aspectWidth):\(\.$aspectHeight)")
			}
		}
	}

	@Parameter(
		title: "Mode",
		description: "Crop by aspect ratio or exact dimensions",
		default: .aspectRatio
	)
	var mode: CropIntentMode

	@Parameter(
		title: "X Position",
		description: "The position of the left side of the crop in pixels. 0 is the left edge of the image.",
		default: 0,
		inclusiveRange: (0, 100_000)
	)
	var x: Int

	@Parameter(
		title: "Y Position",
		description: "The position of the bottom side of the crop in pixels. 0 is the bottom edge of the image.",
		default: 0,
		inclusiveRange: (0, 100_000)
	)
	var y: Int

	@Parameter(
		title: "Width",
		description: "The width of the crop in pixels.",
		default: 1,
		inclusiveRange: (1, 100_000)
	)
	var width: Int

	@Parameter(
		title: "Height",
		description: "The height of the crop in pixels.",
		default: 1,
		inclusiveRange: (1, 100_000)
	)
	var height: Int

	@Parameter(
		title: "Aspect Width",
		description: "The ratio of the width to the height of the crop. For example, 16:9 is the standard for most videos, so 16 is the aspect width and 9 is the aspect height.",
		default: 16,
		inclusiveRange: (1, 99)
	)
	var aspectWidth: Int

	@Parameter(
		title: "Aspect Height",
		description: "The ratio of the width to the height of the crop. For example, 16:9 is the standard for most videos, so 16 is the aspect width and 9 is the aspect height.",
		default: 9,
		inclusiveRange: (1, 99)
	)
	var aspectHeight: Int

	func perform() async throws -> some IntentResult & ReturnsValue<CropEntity> {
		.result(value: entity)
	}

	var entity: CropEntity {
		var entity = CropEntity()
		switch mode {
		case .exact:
			entity.mode = .exact
			entity.x = x
			entity.bottomLeftY = y
			entity.width = width
			entity.height = height
		case .aspectRatio:
			entity.mode = .aspectRatio
			entity.width = aspectWidth
			entity.height = aspectHeight
		}
		return entity
	}
}

struct ConvertIntent: AppIntent, ProgressReportingIntent {
	static let title: LocalizedStringResource = "Convert Video to Animated GIF"

	static let description = IntentDescription(
		"""
		Converts a video to a high-quality animated GIF.
		""",
		searchKeywords: [
			"video",
			"conversion",
			"converter",
			"mp4",
			"mov"
		],
		resultValueName: "Animated GIF"
	)

	@Parameter(
		title: "Video",
		description: "Accepts MP4 and MOV video files.",
		supportedContentTypes: [
			.mpeg4Movie,
			.quickTimeMovie
		]
	)
	var video: IntentFile

	@Parameter(
		title: "Quality",
		default: 1,
		controlStyle: .slider,
		inclusiveRange: (0, 1)
	)
	var quality: Double

	@Parameter(
		title: "Frame Rate",
		description: "By default, it's the same as the video file. Must be in the range 3...50. It will never be higher than the source video. It cannot be above 50 because browsers throttle such frame rates, playing them at 10 FPS.",
		inclusiveRange: (3, 50)
	)
	var frameRate: Int?

	@Parameter(
		title: "Loop",
		description: "Makes the GIF loop forever.",
		default: true
	)
	var loop: Bool

	@Parameter(
		title: "Bounce",
		description: "Makes the GIF play forward and then backwards.",
		default: false
	)
	var bounce: Bool

	@Parameter(
		title: "Dimensions Type",
		description: "Choose how to specify the dimensions.",
		default: DimensionsType.percent
	)
	var dimensionsType: DimensionsType

	@Parameter(
		title: "Dimensions Percent",
		description: "The resize percentage of the original dimensions (1-100%).",
		default: 100,
		inclusiveRange: (1, 100)
	)
	var dimensionsPercent: Double?

	@Parameter(
		title: "Max Width",
		description: "You can specify both width and height or either.",
		inclusiveRange: (10, 10_000)
	)
	var dimensionsWidth: Int?

	@Parameter(
		title: "Max Height",
		description: "You can specify both width and height or either.",
		inclusiveRange: (10, 10_000)
	)
	var dimensionsHeight: Int?

	@Parameter(
		title: "Crop",
		description: "Optionally crop the video.",
	)
	var crop: CropEntity?

	// TODO: Dimensions setting. Percentage or width/height.

	static var parameterSummary: some ParameterSummary {
		Switch(\.$dimensionsType) {
			Case(.pixels) {
				Summary("Convert \(\.$video) to animated GIF") {
					\.$quality
					\.$frameRate
					\.$loop
					\.$bounce
					\.$dimensionsType
					\.$dimensionsWidth
					\.$dimensionsHeight
					\.$crop
				}
			}
			DefaultCase {
				Summary("Convert \(\.$video) to animated GIF") {
					\.$quality
					\.$frameRate
					\.$loop
					\.$bounce
					\.$dimensionsType
					\.$dimensionsPercent
					\.$crop
				}
			}
		}
	}

	@MainActor
	func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
		let videoURL = try video.writeToUniqueTemporaryFile()

		defer {
			try? FileManager.default.removeItem(at: videoURL)
		}

		let (videoAsset, metadata) = try await VideoValidator.validate(videoURL)

		let dimensions: (Int, Int)? = {
			switch dimensionsType {
			case .pixels:
				guard dimensionsWidth != nil || dimensionsHeight != nil else {
					return nil
				}

				let size = metadata.dimensions.aspectFittedSize(
					targetWidth: dimensionsWidth,
					targetHeight: dimensionsHeight
				)

				return (
					Int(size.width.rounded()),
					Int(size.height.rounded())
				)
			case .percent:
				guard let dimensionsPercent else {
					return nil
				}

				let factor = dimensionsPercent / 100

				return (
					Int((metadata.dimensions.width * factor).rounded()),
					Int((metadata.dimensions.height * factor).rounded())
				)
			}
		}()

		let conversion = GIFGenerator.Conversion(
			asset: videoAsset,
			sourceURL: videoURL,
			timeRange: nil,
			quality: quality,
			dimensions: dimensions,
			frameRate: frameRate,
			loop: loop ? .forever : .never,
			bounce: bounce,
			crop: try crop?.cropRect(forDimensions: dimensions ?? metadata.dimensions.toInt)
		)

		// TODO: Progress does not seem to show in the Shortcuts app.

		let generator = GIFGenerator()

		progress.totalUnitCount = 100

		let data = try await generator.run(conversion) { fractionCompleted in
			progress.completedUnitCount = .init(fractionCompleted * 100)
		}

		let file = data.toIntentFile(contentType: .gif, filename: videoURL.filenameWithoutExtension)

		return .result(value: file)
	}
}
