import AppIntents
import AVFoundation

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
		supportedTypeIdentifiers: [
			"public.mpeg-4",
			"com.apple.quicktime-movie"
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
			bounce: bounce
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
