import AppIntents
import AVFoundation

enum CropEntity: AppEntity, Codable {
	case noCrop
	/**
	 The exact coordinates in the image using a *bottom-left* origin (the rest of the app uses top-left origin)
	 */
	case exact(x: Int, y: Int, width: Int, height: Int)
	case aspectRatio(width: Int, height: Int)

	var id: String {
		do {
			return try JSONEncoder().encode(self).base64EncodedString()
		} catch {
			return "0"
		}
	}
	static var defaultQuery = CropEntityQuery()
	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Crop")
	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(title: .init(stringLiteral: description))
	}

	var description: String {
		switch self {
		case .noCrop:
			"No crop"
		case let .aspectRatio(width: width, height: height):
			"\(width):\(height)"
		case let .exact(x: x, y: y, width: width, height: height):
			"\(width)x\(height) at (\(x),\(y))"
		}
	}

	static func from(id: String) throws -> Self {
		guard let data = Data(base64Encoded: id) else {
			throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Invalid ID format"))
		}
		return try JSONDecoder().decode(Self.self, from: data)
	}
	/**
	 Convert from entity to CropRect which uses `UnitPoint` and `UnitSize` and a top-left origin (`.exact` uses a bottom-left origin)
	 */
	func cropRect(forDimensions dimensions: (Int, Int)) throws -> CropRect? {
		let (width, height) = dimensions
		switch self {
		case .noCrop:
			return nil
		case let .exact(x: x, y: bottomLeftY, width: cropWidth, height: cropHeight):
			let topLeftY = height - bottomLeftY - cropHeight
			let entityRect = CGRect(x: x, y: topLeftY, width: cropWidth, height: cropHeight)
			let videoRect = CGRect(origin: .zero, size: .init(width: width, height: height))
			let intersectionRect = videoRect.intersection(entityRect)

			guard intersectionRect.width >= 1,
				  intersectionRect.height >= 1 else {
				throw CropOutOfBounds.cropOutOfBounds(entityRect: entityRect, videoRect: videoRect)
			}
			return CropRect(
				x: Double(intersectionRect.x) / Double(width),
				y: Double(intersectionRect.y) / Double(height),
				width: Double(intersectionRect.width) / Double(width),
				height: Double(intersectionRect.height) / Double(height)
			)
		case let .aspectRatio(width: aspectWidth, height: aspectHeight):
			return CropRect.from(aspectWidth: Double(aspectWidth), aspectHeight: Double(aspectHeight), forDimensions: .init(width: width, height: height))
		}
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
			.aspectRatio(width: $0.width, height: $0.height)
		} + [.noCrop]
	}
}

enum CropIntentMode: String, AppEnum, CaseIterable {
	static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
		.exact: DisplayRepresentation(stringLiteral: "Exact"),
		.aspectRatio: DisplayRepresentation(stringLiteral: "Aspect Ratio")
	]

	case exact
	case aspectRatio

	static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Crop Mode")
}

enum CropOutOfBounds: LocalizedError, CustomNSError {
	case cropOutOfBounds(entityRect: CGRect, videoRect: CGRect)

	var errorDescription: String? {
		switch self {
		case let .cropOutOfBounds(entityRect: entityRect, videoRect: videoRect):
			"Crop rectangle is out of bounds! It's \(entityRect.width)x\(entityRect.height) at \(entityRect.x),\(entityRect.maxY), but it needs to fit inside \(videoRect.width)x\(videoRect.height) for this video."
		}
	}
	var failureReason: String? {
		switch self {
		case .cropOutOfBounds:
			"The crop rectangle is too small."
		}
	}
	var recoverySuggestion: String? {
		switch self {
		case .cropOutOfBounds:
			"Make the crop rectangle larger."
		}
	}
	/**
	 Needed for the error description to show in shortcuts
	 */
	static var errorDomain: String { "CropOutOfBoundsError" }

	var errorCode: Int {
		switch self {
		case .cropOutOfBounds:
			return 1
		}
	}

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
				Summary("Create a crop with exact dimensions") {
					\.$mode
					\.$x
					\.$y
					\.$width
					\.$height
				}
			}
			DefaultCase {
				Summary("Create a crop with a fixed aspect ratio") {
					\.$mode
					\.$aspectWidth
					\.$aspectHeight
				}
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
		switch mode {
		case .exact:
			.exact(x: x, y: y, width: width, height: height)
		case .aspectRatio:
			.aspectRatio(width: aspectWidth, height: aspectHeight)
		}
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
		description: "Optionally crop the video",
		default: .noCrop
	)
	var crop: CropEntity

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
			crop: try crop.cropRect(forDimensions: dimensions ?? metadata.dimensions.toInt)
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
