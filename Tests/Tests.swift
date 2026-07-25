import AVFoundation
import CoreGraphics
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers
import VideoToolbox
@testable import Gifski

struct Tests {
	private func instant(afterSeconds seconds: Double, from startInstant: ContinuousClock.Instant) -> ContinuousClock.Instant {
		startInstant.advanced(by: .seconds(seconds))
	}

	private func seconds(_ duration: Duration) -> Double {
		Double(duration.nanoseconds) / 1_000_000_000
	}

	private func updateAndRequire(
		_ estimator: inout TimeRemainingEstimator,
		progress: Double,
		instant: ContinuousClock.Instant
	) throws -> Duration {
		let timeRemaining = estimator.update(progress: progress, instant: instant)
		return try #require(timeRemaining)
	}

	private func conversion(
		timeRange: ClosedRange<Double>? = nil,
		quality: Double = 1,
		dimensions: (width: Int, height: Int)? = nil,
		frameRate: Int? = nil,
		loop: Gifski.Loop = .never,
		bounce: Bool = false,
		crop: CropRect? = nil,
		trackPreferredTransform: CGAffineTransform? = nil
	) -> GIFGenerator.Conversion {
		let url = URL(filePath: "/dev/null")

		return .init(
			asset: AVURLAsset(url: url),
			sourceURL: url,
			timeRange: timeRange,
			quality: quality,
			dimensions: dimensions,
			frameRate: frameRate,
			loop: loop,
			bounce: bounce,
			crop: crop,
			trackPreferredTransform: trackPreferredTransform
		)
	}

	private func fullPreviewSettings(
		timeRange: ClosedRange<Double>? = nil,
		speed: Double = 1,
		frameRate: Int = 10,
		duration: Duration = .seconds(10)
	) -> SettingsForFullPreview {
		// Defaults keep each preview-reuse test focused on only the setting it changes.
		.init(
			conversion: conversion(timeRange: timeRange),
			speed: speed,
			frameRate: frameRate,
			assetDuration: duration
		)
	}

	private func pixelBuffer() throws -> CVPixelBuffer {
		var pixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			nil,
			1,
			1,
			kCVPixelFormatType_32BGRA,
			nil,
			&pixelBuffer
		)
		#expect(status == kCVReturnSuccess)
		return try #require(pixelBuffer)
	}

	private func makeTestVideo() async throws -> URL {
		try await makeTestVideo(frameCount: 4) { frameNumber in
			let color = UInt8(frameNumber * 60)
			return try makePixelBuffer(red: color, green: 255 - color, blue: color / 2)
		}
	}

	private func makeHorizontalSplitTestVideo() async throws -> URL {
		try await makeTestVideo(frameCount: 3) { _ in
			try makeHorizontalSplitPixelBuffer()
		}
	}

	private func makeTestVideo(
		frameCount: Int,
		codec: AVVideoCodecType = .h264,
		presentationTimeForFrame: (Int) -> CMTime = { .init(value: CMTimeValue($0), timescale: 2) },
		pixelBufferForFrame: (Int) throws -> CVPixelBuffer
	) async throws -> URL {
		let directory = try URL.uniqueTemporaryDirectory()
		let outputURL = directory.appending(path: "test.mov")
		let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
		let input = AVAssetWriterInput(
			mediaType: .video,
			outputSettings: [
				AVVideoCodecKey: codec,
				AVVideoWidthKey: 16,
				AVVideoHeightKey: 16
			]
		)
		input.expectsMediaDataInRealTime = false

		let adaptor = AVAssetWriterInputPixelBufferAdaptor(
			assetWriterInput: input,
			sourcePixelBufferAttributes: [
				kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
				kCVPixelBufferWidthKey as String: 16,
				kCVPixelBufferHeightKey as String: 16
			]
		)

		try #require(writer.canAdd(input))
		writer.add(input)

		try #require(writer.startWriting())
		writer.startSession(atSourceTime: .zero)

		for frameNumber in 0..<frameCount {
			for _ in 0..<100 {
				guard !input.isReadyForMoreMediaData else {
					break
				}
				if let error = writer.error {
					throw error
				}
				try await Task.sleep(for: .milliseconds(10))
			}
			try #require(input.isReadyForMoreMediaData)

			let pixelBuffer = try pixelBufferForFrame(frameNumber)
			let presentationTime = presentationTimeForFrame(frameNumber)
			try #require(adaptor.append(pixelBuffer, withPresentationTime: presentationTime))
		}

		input.markAsFinished()
		await writer.finishWriting()

		if let error = writer.error {
			throw error
		}
		try #require(writer.status == .completed)
		return outputURL
	}

	/**
	Returns the bundled variable-frame-rate fixture used by the video-composition regression tests.
	*/
	private func variableFrameRateTestVideoURL() throws -> URL {
		guard let url = #bundle.url(forResource: "variable-frame-rate-zero-minimum-duration", withExtension: "mp4") else {
			throw "Missing variable-frame-rate test fixture.".toError
		}

		return url
	}

	/**
	Returns the presentation timestamps of every non-empty sample, optionally rendering the track through a video composition.
	*/
	private func presentationTimestamps(for videoTrack: AVAssetTrack, videoComposition: AVVideoComposition? = nil) async throws -> [CMTime] {
		let asset = try #require(videoTrack.asset)
		let reader = try AVAssetReader(asset: asset)
		let output: AVAssetReaderOutput
		if let videoComposition {
			let compositionOutput = AVAssetReaderVideoCompositionOutput(videoTracks: [videoTrack], videoSettings: CVPixelBuffer.bgra32Attributes)
			compositionOutput.videoComposition = videoComposition
			output = compositionOutput
		} else {
			output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
		}
		let provider = reader.outputProvider(for: output)
		try reader.start()
		defer {
			if reader.status == .reading {
				reader.cancelReading()
			}
		}

		var timestamps = [CMTime]()
		while let sampleBuffer = try await provider.next() {
			guard sampleBuffer.sampleCount > 0 else {
				continue
			}

			timestamps.append(sampleBuffer.outputPresentationTimeStamp)
		}

		return timestamps.sorted()
	}

	/**
	Checks that two timestamp collections describe the same presentation timing after normalizing their start times.
	*/
	private func expectSamePresentationTiming(_ expectedTimestamps: [CMTime], _ actualTimestamps: [CMTime]) throws {
		try #require(actualTimestamps.count == expectedTimestamps.count)

		let expectedStart = try #require(expectedTimestamps.first)
		let actualStart = try #require(actualTimestamps.first)
		for (expectedTimestamp, actualTimestamp) in zip(expectedTimestamps, actualTimestamps) {
			let normalizedExpectedTimestamp = (expectedTimestamp - expectedStart).seconds
			let normalizedActualTimestamp = (actualTimestamp - actualStart).seconds
			#expect(abs(normalizedActualTimestamp - normalizedExpectedTimestamp) < 0.001)
		}
	}

	private func makePixelBuffer(
		red: UInt8,
		green: UInt8,
		blue: UInt8
	) throws -> CVPixelBuffer {
		try makePixelBuffer { _, _ in
			(red, green, blue)
		}
	}

	private func makeHorizontalSplitPixelBuffer() throws -> CVPixelBuffer {
		try makePixelBuffer { x, width in
			let red: UInt8 = x < width / 2 ? 255 : 0
			return (red, 0, 0)
		}
	}

	private func makePixelBuffer(pixelColor: (_ x: Int, _ totalWidth: Int) -> (red: UInt8, green: UInt8, blue: UInt8)) throws -> CVPixelBuffer {
		var newPixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			nil,
			16,
			16,
			kCVPixelFormatType_32BGRA,
			nil,
			&newPixelBuffer
		)
		try #require(status == kCVReturnSuccess)
		let pixelBuffer = try #require(newPixelBuffer)

		CVPixelBufferLockBaseAddress(pixelBuffer, [])
		defer {
			CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
		}

		guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
			throw "Could not access pixel buffer storage.".toError
		}

		let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
		let height = CVPixelBufferGetHeight(pixelBuffer)
		let width = CVPixelBufferGetWidth(pixelBuffer)
		let buffer = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

		for y in 0..<height {
			for x in 0..<width {
				let offset = (y * bytesPerRow) + (x * 4)
				let color = pixelColor(x, width)
				buffer[offset] = color.blue
				buffer[offset + 1] = color.green
				buffer[offset + 2] = color.red
				buffer[offset + 3] = 255
			}
		}

		return pixelBuffer
	}

	/**
	Left half opaque red, right half fully transparent.
	*/
	private func makeTransparentPixelBuffer() throws -> CVPixelBuffer {
		var newPixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			nil,
			16,
			16,
			kCVPixelFormatType_32BGRA,
			nil,
			&newPixelBuffer
		)
		try #require(status == kCVReturnSuccess)
		let pixelBuffer = try #require(newPixelBuffer)

		CVPixelBufferLockBaseAddress(pixelBuffer, [])
		defer {
			CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
		}

		guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
			throw "Could not access pixel buffer storage.".toError
		}

		let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
		let height = CVPixelBufferGetHeight(pixelBuffer)
		let width = CVPixelBufferGetWidth(pixelBuffer)
		let buffer = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

		for y in 0..<height {
			for x in 0..<width {
				let offset = (y * bytesPerRow) + (x * 4)
				let isOpaque = x < width / 2
				buffer[offset] = 0 // Blue
				buffer[offset + 1] = 0 // Green
				buffer[offset + 2] = isOpaque ? 255 : 0 // Red
				buffer[offset + 3] = isOpaque ? 255 : 0 // Alpha
			}
		}

		return pixelBuffer
	}

	private func transparentPixelCount(gifData: Data, frameIndex: Int) throws -> Int {
		let imageSource = try #require(CGImageSourceCreateWithData(gifData as CFData, nil))
		let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, frameIndex, nil))
		return try transparentPixelCount(in: image)
	}

	/**
	Counts fully transparent pixels in a decoded image, independently of whether its format declares an alpha channel.
	*/
	private func transparentPixelCount(in image: CGImage) throws -> Int {
		let width = image.width
		let height = image.height
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		let context = try #require(CGContext(
			data: &pixels,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))

		context.draw(image, in: .init(x: 0, y: 0, width: Double(width), height: Double(height)))

		var count = 0
		for offset in stride(from: 3, to: pixels.count, by: 4) where pixels[offset] == 0 {
			count += 1
		}

		return count
	}

	private func makeHorizontalSplitCGImage() throws -> CGImage {
		let pixelBuffer = try makeHorizontalSplitPixelBuffer()
		var cgImage: CGImage?
		let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
		try #require(status == noErr)
		return try #require(cgImage)
	}

	private func gifFrameCount(_ gifData: Data) throws -> Int {
		let imageSource = try #require(CGImageSourceCreateWithData(gifData as CFData, nil))
		return CGImageSourceGetCount(imageSource)
	}

	private func imageDimensions(gifData: Data) throws -> CGSize {
		let imageSource = try #require(CGImageSourceCreateWithData(gifData as CFData, nil))
		let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
		return .init(width: image.width, height: image.height)
	}

	private func averageRedValue(gifData: Data, frameIndex: Int) throws -> Double {
		let imageSource = try #require(CGImageSourceCreateWithData(gifData as CFData, nil))
		let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, frameIndex, nil))
		let width = image.width
		let height = image.height
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		let context = try #require(CGContext(
			data: &pixels,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		))

		context.draw(image, in: .init(x: 0, y: 0, width: Double(width), height: Double(height)))

		var redTotal = 0
		for offset in stride(from: 0, to: pixels.count, by: 4) {
			redTotal += Int(pixels[offset])
		}

		return Double(redTotal) / Double(width * height)
	}

	@Test
	func exportModifiedVideoStateUpdatesProgressSheetVisibilityOnlyWhileExporting() {
		let task = Task {}
		defer {
			task.cancel()
		}
		var state = ExportModifiedVideoState.exporting(task, shouldShowProgressSheet: false)

		let updatedWhileExporting = state.updateProgressSheetVisibility(true)

		#expect(updatedWhileExporting)
		#expect(state == .exporting(task, shouldShowProgressSheet: true))

		state = .idle

		let updatedWhileIdle = state.updateProgressSheetVisibility(true)

		#expect(!updatedWhileIdle)
		#expect(state == .idle)

		state = .finished(URL(filePath: "/dev/null"))

		let updatedWhileFinished = state.updateProgressSheetVisibility(true)

		#expect(!updatedWhileFinished)
		#expect(state == .finished(URL(filePath: "/dev/null")))
	}

	@Test
	func `frame duration is derived from frame rate`() {
		#expect(CMTime.frameDuration(frameRate: 24) == .init(value: 1, timescale: 24))
		#expect(CMTime.frameDuration(frameRate: 2000) == .init(value: 1, timescale: 2000))
	}

	@Test
	func `frame duration preserves fractional frame rates`() {
		#expect(CMTime.frameDuration(frameRate: 23.976) == .init(value: 1001, timescale: 24_000))
		#expect(CMTime.frameDuration(frameRate: 29.97) == .init(value: 1001, timescale: 30_000))
		#expect(CMTime.frameDuration(frameRate: 59.94) == .init(value: 1001, timescale: 60_000))
	}

	@Test
	func `frame duration is nil for unusable frame rates`() {
		#expect(CMTime.frameDuration(frameRate: 0) == nil)
		#expect(CMTime.frameDuration(frameRate: -24) == nil)
		#expect(CMTime.frameDuration(frameRate: .nan) == nil)
		#expect(CMTime.frameDuration(frameRate: .infinity) == nil)
		#expect(CMTime.frameDuration(frameRate: .greatestFiniteMagnitude) == nil)
	}

	@Test
	func `positive time excludes zero, negative, and non-numeric times`() {
		#expect(CMTime(value: 1, timescale: 24).isPositive)
		#expect(!CMTime.zero.isPositive)
		#expect(!CMTime(value: -1, timescale: 24).isPositive)
		#expect(!CMTime.invalid.isPositive)
		#expect(!CMTime.indefinite.isPositive)
		#expect(!CMTime.positiveInfinity.isPositive)
	}

	@Test
	func `common cancellation errors are recognized`() {
		let errors: [Error] = [
			CancellationError(),
			URLError(.cancelled),
			CocoaError(.userCancelled),
			NSError(domain: AVFoundationErrorDomain, code: AVError.operationCancelled.rawValue)
		]

		for error in errors {
			#expect(error.isCancelled)
		}
	}

	@Test
	func `ordinary errors are not treated as cancellation`() {
		let errors: [Error] = [
			URLError(.timedOut),
			CocoaError(.fileReadNoSuchFile),
			NSError(domain: AVFoundationErrorDomain, code: AVError.exportFailed.rawValue),
			NSError(domain: "UnrelatedError", code: URLError.cancelled.rawValue)
		]

		for error in errors {
			#expect(!error.isCancelled)
		}
	}

	@Test
	func keyframeInfoCancelsCompressedSampleReadOnExit() async throws {
		let videoURL = try await makeTestVideo()
		let asset = AVURLAsset(url: videoURL)
		let track = try #require(try await asset.firstVideoTrack)

		let info = try #require(try await track.keyframeInfo())

		#expect(info.frameCount == 4)
		#expect(info.keyframeCount > 0)
	}

	@Test
	func blankFrameTrimmingCancelsCompressedSampleReadOnExit() async throws {
		let videoURL = try await makeTestVideo()
		let asset = AVURLAsset(url: videoURL)
		let track = try #require(try await asset.firstVideoTrack)
		let originalTimeRange = try await track.load(.timeRange)

		let trimmedTrack = try await track.trimmingBlankFrames()
		let trimmedTimeRange = try await trimmedTrack.load(.timeRange)

		#expect(trimmedTimeRange == originalTimeRange)
	}

	@Test
	func fullPreviewWithNoGeneratedFramesThrowsInsteadOfCrashing() async throws {
		let event = FullPreviewGenerationEvent.ready(
			settings: .init(
				conversion: conversion(),
				speed: 1,
				frameRate: 10,
				assetDuration: .seconds(1)
			),
			gifData: [],
			requestID: 0
		)

		let originalFrame = try pixelBuffer()

		await #expect(throws: (any Error).self) {
			_ = try await event.getPreviewFrame(
				originalFrame: originalFrame,
				compositionTime: .zero
			)
		}
	}

	@Test
	func fullPreviewReusesReadyPreviewWhenNewTimeRangeIsContained() {
		// A finished full preview can satisfy narrower trim ranges because it already has frames for the requested slice.
		let oldSettings = fullPreviewSettings(timeRange: 0...10)
		let newSettings = fullPreviewSettings(timeRange: 2...4)

		let needsNewPreview = oldSettings.areSettingsDifferentEnoughForANewFullPreview(
			newSettings: newSettings,
			areCurrentlyGenerating: false,
			oldRequestID: 1,
			newRequestID: 2
		)

		#expect(!needsNewPreview)
	}

	@Test
	func fullPreviewRegeneratesForContainedTimeRangeWhileGenerating() {
		// While generation is in progress, there is no completed frame cache to slice from yet.
		let oldSettings = fullPreviewSettings(timeRange: 0...10)
		let newSettings = fullPreviewSettings(timeRange: 2...4)

		let needsNewPreview = oldSettings.areSettingsDifferentEnoughForANewFullPreview(
			newSettings: newSettings,
			areCurrentlyGenerating: true,
			oldRequestID: 1,
			newRequestID: 2
		)

		#expect(needsNewPreview)
	}

	@Test
	func fullPreviewRegeneratesWhenFrameRateChanges() {
		let oldSettings = fullPreviewSettings(frameRate: 10)
		let newSettings = fullPreviewSettings(frameRate: 12)

		let needsNewPreview = oldSettings.areSettingsDifferentEnoughForANewFullPreview(
			newSettings: newSettings,
			areCurrentlyGenerating: false,
			oldRequestID: 1,
			newRequestID: 2
		)

		#expect(needsNewPreview)
	}

	@Test
	func fullPreviewRegeneratesWhenAssetDurationChanges() {
		let oldSettings = fullPreviewSettings(duration: .seconds(10))
		let newSettings = fullPreviewSettings(duration: .seconds(12))

		let needsNewPreview = oldSettings.areSettingsDifferentEnoughForANewFullPreview(
			newSettings: newSettings,
			areCurrentlyGenerating: false,
			oldRequestID: 1,
			newRequestID: 2
		)

		#expect(needsNewPreview)
	}

	@Test
	func fullPreviewReusesReadyPreviewWhenBothTimeRangesAreNil() {
		let oldSettings = fullPreviewSettings()
		let newSettings = fullPreviewSettings()

		let needsNewPreview = oldSettings.areSettingsDifferentEnoughForANewFullPreview(
			newSettings: newSettings,
			areCurrentlyGenerating: false,
			oldRequestID: 1,
			newRequestID: 2
		)

		#expect(!needsNewPreview)
	}

	@Test
	func fullPreviewReusesReadyPreviewWhenOldTimeRangeIsNilAndNewIsExplicit() {
		// nil means the full duration was previewed, so any explicit sub-range is a subset.
		let oldSettings = fullPreviewSettings()
		let newSettings = fullPreviewSettings(timeRange: 2...4)

		let needsNewPreview = oldSettings.areSettingsDifferentEnoughForANewFullPreview(
			newSettings: newSettings,
			areCurrentlyGenerating: false,
			oldRequestID: 1,
			newRequestID: 2
		)

		#expect(!needsNewPreview)
	}

	@Test
	func fullPreviewRegeneratesWhenNewTimeRangeIsWiderThanOld() {
		// Old previewed a sub-range, new wants the full duration.
		let oldSettings = fullPreviewSettings(timeRange: 2...4)
		let newSettings = fullPreviewSettings()

		let needsNewPreview = oldSettings.areSettingsDifferentEnoughForANewFullPreview(
			newSettings: newSettings,
			areCurrentlyGenerating: false,
			oldRequestID: 1,
			newRequestID: 2
		)

		#expect(needsNewPreview)
	}

	@Test
	func fullPreviewRegeneratesWhenSpeedChanges() {
		let oldSettings = fullPreviewSettings(speed: 1)
		let newSettings = fullPreviewSettings(speed: 2)

		let needsNewPreview = oldSettings.areSettingsDifferentEnoughForANewFullPreview(
			newSettings: newSettings,
			areCurrentlyGenerating: false,
			oldRequestID: 1,
			newRequestID: 2
		)

		#expect(needsNewPreview)
	}

	@Test
	func fullPreviewConversionUsesExplicitPreviewFrameRate() {
		// Full preview strips loop/bounce, but must use the frame rate already adjusted for output speed.
		let settings = SettingsForFullPreview(
			conversion: conversion(
				timeRange: 2...4,
				dimensions: (width: 320, height: 240),
				frameRate: 50,
				loop: .forever,
				bounce: true,
				trackPreferredTransform: .init(translationX: 10, y: 20)
			),
			speed: 1,
			frameRate: 12,
			assetDuration: .seconds(10)
		)

		let converted = settings.conversion.toConversion(
			asset: AVURLAsset(url: URL(filePath: "/dev/null")),
			frameRate: settings.frameRate
		)

		#expect(converted.timeRange == 2...4)
		#expect(converted.dimensions?.width == 320)
		#expect(converted.dimensions?.height == 240)
		#expect(converted.frameRate == 12)
		#expect(!converted.loop.isLooping)
		#expect(!converted.bounce)
		#expect(converted.trackPreferredTransform == .init(translationX: 10, y: 20))
	}

	@Test
	func gifGenerationReadsFramesFromVideoAsset() async throws {
		let videoURL = try await makeTestVideo()
		defer {
			try? videoURL.deletingLastPathComponent().delete()
		}

		let data = try await GIFGenerator.run(
			.init(
				asset: AVURLAsset(url: videoURL),
				sourceURL: videoURL,
				timeRange: 0...1.5,
				quality: 0.8,
				dimensions: (width: 8, height: 8),
				frameRate: 2,
				loop: .never,
				bounce: false,
				crop: .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
			)
		) { _ in }

		#expect(data.starts(with: Data("GIF".utf8)))
		#expect(try imageDimensions(gifData: data) == .init(width: 8, height: 8))
		#expect(try gifFrameCount(data) == 4)

		let previousFrameRedValue = try averageRedValue(gifData: data, frameIndex: 2)
		let endFrameRedValue = try averageRedValue(gifData: data, frameIndex: 3)
		#expect(endFrameRedValue > previousFrameRedValue + 20)
	}

	@Test
	func gifGenerationWithBounceProducesCorrectFrameCount() async throws {
		let videoURL = try await makeTestVideo()
		defer {
			try? videoURL.deletingLastPathComponent().delete()
		}

		let data = try await GIFGenerator.run(
			.init(
				asset: AVURLAsset(url: videoURL),
				sourceURL: videoURL,
				timeRange: 0...1.5,
				quality: 0.8,
				dimensions: (width: 8, height: 8),
				frameRate: 2,
				loop: .never,
				bounce: true
			)
		) { _ in }

		#expect(data.starts(with: Data("GIF".utf8)))
		// 1.5s at 2fps = 3 frames, bounce doubles minus apex = 3*2-1 = 5
		#expect(try gifFrameCount(data) == 5)
	}

	@Test
	func gifEstimationSucceedsWithFullAppPipeline() async throws {
		let videoURL = try await makeTestVideo(frameCount: 60) { frameNumber in
			let color = UInt8(frameNumber % 256)
			return try makePixelBuffer(red: color, green: 255 - color, blue: color / 2)
		}
		defer {
			try? videoURL.deletingLastPathComponent().delete()
		}

		let (validatedAsset, metadata) = try await VideoValidator.validate(videoURL)
		let previewable = try await PreviewableComposition(asset: validatedAsset)

		let generator = GIFGenerator()
		let data = try await generator.run(
			.init(
				asset: previewable,
				sourceURL: videoURL,
				quality: 0.5,
				dimensions: (width: 8, height: 8),
				frameRate: 2,
				loop: .never,
				bounce: false,
				trackPreferredTransform: metadata.trackPreferredTransform
			),
			isEstimation: true
		) { _ in }

		#expect(data.starts(with: Data("GIF".utf8)))
		#expect(await generator.sizeMultiplierForEstimation > 1)
	}

	@Test(arguments: [4, 10, 30, 50])
	func gifEstimationSucceedsWithRealVideoFile(fps: Int) async throws {
		let videoURL = URL(filePath: "/Users/sindresorhus/dev/project-extras/Gifski/Fixture/60fps - short.mp4")
		guard videoURL.exists else {
			return
		}

		let (validatedAsset, metadata) = try await VideoValidator.validate(videoURL)

		let generator = GIFGenerator()
		let data = try await generator.run(
			.init(
				asset: validatedAsset,
				sourceURL: videoURL,
				quality: 0.5,
				dimensions: (width: 320, height: 180),
				frameRate: fps,
				loop: .never,
				bounce: false,
				trackPreferredTransform: metadata.trackPreferredTransform
			),
			isEstimation: true
		) { _ in }

		#expect(data.starts(with: Data("GIF".utf8)))
	}

	@Test
	func gifGenerationUsesSelectedCropRegion() async throws {
		let videoURL = try await makeHorizontalSplitTestVideo()
		defer {
			try? videoURL.deletingLastPathComponent().delete()
		}

		let leftCropData = try await GIFGenerator.run(
			.init(
				asset: AVURLAsset(url: videoURL),
				sourceURL: videoURL,
				timeRange: 0...1,
				quality: 0.8,
				dimensions: (width: 8, height: 16),
				frameRate: 2,
				loop: .never,
				bounce: false,
				crop: .init(x: 0, y: 0, width: 0.5, height: 1)
			)
		) { _ in }

		let rightCropData = try await GIFGenerator.run(
			.init(
				asset: AVURLAsset(url: videoURL),
				sourceURL: videoURL,
				timeRange: 0...1,
				quality: 0.8,
				dimensions: (width: 8, height: 16),
				frameRate: 2,
				loop: .never,
				bounce: false,
				crop: .init(x: 0.5, y: 0, width: 0.5, height: 1)
			)
		) { _ in }

		#expect(try imageDimensions(gifData: leftCropData) == .init(width: 8, height: 16))
		#expect(try imageDimensions(gifData: rightCropData) == .init(width: 8, height: 16))
		#expect(try averageRedValue(gifData: leftCropData, frameIndex: 0) > 200)
		#expect(try averageRedValue(gifData: rightCropData, frameIndex: 0) < 50)
	}

	@Test
	func gifGenerationPreservesAlphaFromProRes4444Source() async throws {
		let videoURL = try await makeTestVideo(frameCount: 3, codec: .proRes4444) { _ in
			try makeTransparentPixelBuffer()
		}
		defer {
			try? videoURL.deletingLastPathComponent().delete()
		}

		let data = try await GIFGenerator.run(
			.init(
				asset: AVURLAsset(url: videoURL),
				sourceURL: videoURL,
				timeRange: 0...1,
				quality: 0.8,
				dimensions: (width: 16, height: 16),
				frameRate: 2,
				loop: .never,
				bounce: false
			)
		) { _ in }

		#expect(data.starts(with: Data("GIF".utf8)))

		// The transparent right half of the ProRes 4444 source (128 of the 256 pixels) must survive as transparency in the GIF. The built-in video compositor flattened it to opaque, which is the bug this guards against. The bounds bracket the expected ~128 while allowing slight quantization slack.
		let transparentCount = try transparentPixelCount(gifData: data, frameIndex: 0)
		#expect(transparentCount > 96)
		#expect(transparentCount < 160)
	}

	@Test
	func exportModifiedVideoCreatesMovieFromVideoAsset() async throws {
		let videoURL = try await makeTestVideo()
		defer {
			try? videoURL.deletingLastPathComponent().delete()
		}

		let outputURL = try await exportModifiedVideo(
			conversion: .init(
				asset: AVURLAsset(url: videoURL),
				sourceURL: videoURL,
				timeRange: 0...1.5,
				quality: 1,
				dimensions: (width: 8, height: 8),
				frameRate: 2,
				loop: .never,
				bounce: false,
				crop: .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
			)
		)
		defer {
			try? outputURL.delete()
		}

		let asset = AVURLAsset(url: outputURL)
		#expect(outputURL.exists)
		#expect(try await asset.dimensions == .init(width: 8, height: 8))
		#expect(try await asset.load(.duration).seconds > 0)
	}

	@Test
	func `modified video export preserves variable frame rate timing`() async throws {
		let videoURL = try variableFrameRateTestVideoURL()

		let asset = AVURLAsset(url: videoURL)
		let videoTrack = try #require(try await asset.firstVideoTrack)
		#expect(try await videoTrack.load(.minFrameDuration) == .zero)
		let sourceTimestamps = try await presentationTimestamps(for: videoTrack)
		let sourceFrameIntervals = zip(sourceTimestamps, sourceTimestamps.dropFirst()).map { $1 - $0 }
		let firstSourceFrameInterval = try #require(sourceFrameIntervals.first)
		#expect(sourceFrameIntervals.contains { $0 != firstSourceFrameInterval })
		let previewableComposition = try await PreviewableComposition(asset: asset)

		let outputURL = try await exportModifiedVideo(
			conversion: .init(
				asset: previewableComposition,
				sourceURL: videoURL,
				quality: 1,
				dimensions: (width: 8, height: 8),
				frameRate: 2,
				loop: .never,
				bounce: false
			)
		)
		defer {
			try? outputURL.delete()
		}

		let outputAsset = AVURLAsset(url: outputURL)
		let outputVideoTrack = try #require(try await outputAsset.firstVideoTrack)
		let outputTimestamps = try await presentationTimestamps(for: outputVideoTrack)
		#expect(outputURL.exists)
		#expect(try await outputAsset.dimensions == .init(width: 8, height: 8))
		#expect(try await outputAsset.load(.duration).seconds > 0)
		try expectSamePresentationTiming(sourceTimestamps, outputTimestamps)
	}

	@Test
	func `previewable composition renders variable frame rate video at nominal frame rate`() async throws {
		let videoURL = try variableFrameRateTestVideoURL()

		let asset = AVURLAsset(url: videoURL)
		let videoTrack = try #require(try await asset.firstVideoTrack)
		#expect(try await videoTrack.load(.minFrameDuration) == .zero)
		#expect(try await videoTrack.frameRate == 4)

		let previewableComposition = try await PreviewableComposition(asset: asset)
		let previewableVideoTrack = try #require(try await previewableComposition.firstVideoTrack)
		#expect(previewableComposition.videoComposition.frameDuration == .init(value: 1, timescale: 4))
		#expect(previewableComposition.videoComposition.sourceTrackIDForFrameTiming == kCMPersistentTrackID_Invalid)
		let previewTimestamps = try await presentationTimestamps(for: previewableVideoTrack, videoComposition: previewableComposition.videoComposition)
		// The source frame at 1/6 second becomes a new 4 FPS GIF frame at 1/4 second. Source-timed rendering skips that preview update.
		#expect(previewTimestamps.contains(.init(value: 1, timescale: 4)))
	}

	@Test
	func `previewable composition uses speed adjusted frame rate`() async throws {
		let videoURL = try await makeTestVideo()
		defer {
			try? videoURL.deletingLastPathComponent().delete()
		}

		let asset = AVURLAsset(url: videoURL)
		let sourceVideoTrack = try #require(try await asset.firstVideoTrack)
		let speedAdjustedAsset = try #require(try await sourceVideoTrack.extractToNewAssetAndChangeSpeed(to: 2))
		let speedAdjustedVideoTrack = try #require(try await speedAdjustedAsset.firstVideoTrack)
		#expect(try await speedAdjustedVideoTrack.frameRate == 4)
		#expect(try await speedAdjustedVideoTrack.load(.minFrameDuration) == .init(value: 1, timescale: 2))
		let speedAdjustedTimestamps = try await presentationTimestamps(for: speedAdjustedVideoTrack)

		let previewableComposition = try await PreviewableComposition(asset: speedAdjustedAsset)
		#expect(previewableComposition.videoComposition.frameDuration == .init(value: 1, timescale: 4))

		let outputURL = try await exportModifiedVideo(
			conversion: .init(
				asset: previewableComposition,
				sourceURL: videoURL,
				quality: 1,
				dimensions: (width: 16, height: 16),
				frameRate: 2,
				loop: .never,
				bounce: false
			)
		)
		defer {
			try? outputURL.delete()
		}

		let outputAsset = AVURLAsset(url: outputURL)
		let outputVideoTrack = try #require(try await outputAsset.firstVideoTrack)
		let outputTimestamps = try await presentationTimestamps(for: outputVideoTrack)
		try expectSamePresentationTiming(speedAdjustedTimestamps, outputTimestamps)
	}

	@Test(arguments: [[0, 2, 4, 6], [0, 1, 4, 6]])
	func `modified video export preserves alpha and source frame timing`(frameOffsets: [Int]) async throws {
		let sourceTimestamps = frameOffsets.map { CMTime(value: CMTimeValue($0), timescale: 4) }
		let videoURL = try await makeTestVideo(
			frameCount: sourceTimestamps.count,
			codec: .proRes4444,
			presentationTimeForFrame: { sourceTimestamps[$0] }
		) { _ in
			try makeTransparentPixelBuffer()
		}
		defer {
			try? videoURL.deletingLastPathComponent().delete()
		}

		let asset = AVURLAsset(url: videoURL)
		let previewableComposition = try await PreviewableComposition(asset: asset)
		let outputURL = try await exportModifiedVideo(
			conversion: .init(
				asset: previewableComposition,
				sourceURL: videoURL,
				quality: 1,
				dimensions: (width: 16, height: 16),
				frameRate: 2,
				loop: .never,
				bounce: false
			)
		)
		defer {
			try? outputURL.delete()
		}

		// An alpha-capable source must export as an alpha-capable format (HEVC with alpha in a `.mov`) so transparency is not flattened.
		#expect(outputURL.pathExtension == "mov")
		let outputAsset = AVURLAsset(url: outputURL)
		let outputTrack = try #require(try await outputAsset.firstVideoTrack)
		#expect(try await outputTrack.hasAlphaChannel)
		let outputTimestamps = try await presentationTimestamps(for: outputTrack)
		try expectSamePresentationTiming(sourceTimestamps, outputTimestamps)

		for timestamp in outputTimestamps {
			let image = try #require(try await outputAsset.image(at: timestamp))
			// The right half must remain transparent, while the left half must remain opaque.
			let transparentCount = try transparentPixelCount(in: image)
			#expect(transparentCount > 96)
			#expect(transparentCount < 160)
		}
	}

	@Test
	func effectiveFrameRateRangeUsesSpeedAdjustedVideoFrameRate() {
		#expect(29.97.effectiveFrameRateRange(speed: 1) == 3...30)
		#expect(29.97.effectiveFrameRateRange(speed: 2) == 3...50)
		#expect(29.97.effectiveFrameRateRange(speed: 0.5) == 3...15)
		#expect(120.0.effectiveFrameRateRange(speed: 1) == 3...50)
		#expect(2.0.effectiveFrameRateRange(speed: 1) == 3...3)
	}

	@Test
	func timeRemainingEstimatorReturnsNilUntilProgressAdvances() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 0.5)
		let startInstant = ContinuousClock().now

		#expect(estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant)) == nil)
		#expect(estimator.update(progress: 0.1, instant: instant(afterSeconds: 1, from: startInstant)) == nil)

		let timeRemaining = try updateAndRequire(&estimator, progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))
		#expect(timeRemaining > .zero)
	}

	@Test
	func timeRemainingEstimatorUsesExponentialSmoothing() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 0.5)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		_ = estimator.update(progress: 0.3, instant: instant(afterSeconds: 2, from: startInstant))

		let timeRemaining = try updateAndRequire(&estimator, progress: 0.4, instant: instant(afterSeconds: 4, from: startInstant))

		let expectedTimeRemaining = 8.0
		let difference = abs(seconds(timeRemaining) - expectedTimeRemaining)
		#expect(difference < 0.0001)
	}

	@Test
	func timeRemainingEstimatorIgnoresZeroTimeDeltaForSpeedUpdates() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 1)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		let baselineRemaining = try updateAndRequire(&estimator, progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))

		let unchangedTimeRemaining = try updateAndRequire(&estimator, progress: 0.3, instant: instant(afterSeconds: 2, from: startInstant))
		let unchangedDifference = abs(seconds(unchangedTimeRemaining) - 14.0)
		#expect(unchangedDifference < 0.0001)

		let laterTimeRemaining = try updateAndRequire(&estimator, progress: 0.4, instant: instant(afterSeconds: 4, from: startInstant))
		#expect(laterTimeRemaining < baselineRemaining)
	}

	@Test
	func timeRemainingEstimatorUsesInstantaneousSpeedWhenSmoothingFactorIsOne() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 1)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		_ = estimator.update(progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))

		let timeRemaining = try updateAndRequire(&estimator, progress: 0.4, instant: instant(afterSeconds: 3, from: startInstant))

		let expectedTimeRemaining = 3.0
		let difference = abs(seconds(timeRemaining) - expectedTimeRemaining)
		#expect(difference < 0.0001)
	}

	@Test
	func timeRemainingEstimatorReturnsZeroAtCompletion() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 0.5)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		_ = estimator.update(progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))

		let timeRemaining = try updateAndRequire(&estimator, progress: 1, instant: instant(afterSeconds: 4, from: startInstant))
		#expect(timeRemaining == .zero)
	}

	@Test
	func timeRemainingEstimatorHandlesRegressingProgress() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 1)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		let baselineRemaining = try updateAndRequire(&estimator, progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))

		let regressedRemaining = try updateAndRequire(&estimator, progress: 0.15, instant: instant(afterSeconds: 3, from: startInstant))
		#expect(regressedRemaining > baselineRemaining)
	}

	@Test
	func timeRemainingEstimatorDecreasesWithConstantSpeed() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 1)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		let firstRemaining = try updateAndRequire(&estimator, progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))
		let secondRemaining = try updateAndRequire(&estimator, progress: 0.3, instant: instant(afterSeconds: 4, from: startInstant))
		let thirdRemaining = try updateAndRequire(&estimator, progress: 0.4, instant: instant(afterSeconds: 6, from: startInstant))

		#expect(secondRemaining < firstRemaining)
		#expect(thirdRemaining < secondRemaining)
	}

	@Test
	func timeRemainingEstimatorIgnoresSamplesBelowMinimumInterval() async throws {
		var estimator = TimeRemainingEstimator(
			smoothingFactor: 1,
			minimumSampleInterval: .seconds(1)
		)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		#expect(estimator.update(progress: 0.2, instant: instant(afterSeconds: 0.5, from: startInstant)) == nil)

		let timeRemaining = try updateAndRequire(&estimator, progress: 0.3, instant: instant(afterSeconds: 1.5, from: startInstant))

		let expectedTimeRemaining = 5.25
		let difference = abs(seconds(timeRemaining) - expectedTimeRemaining)
		#expect(difference < 0.0001)
	}

	@Test
	func timeRemainingEstimatorQuantizesSeconds() async throws {
		let quantizedRemaining = TimeRemainingEstimator.quantizedRemaining(
			remaining: .seconds(41),
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)

		#expect(quantizedRemaining == .seconds(40))
	}

	@Test
	func timeRemainingEstimatorClampsSubStepSeconds() async throws {
		let quantizedRemaining = TimeRemainingEstimator.quantizedRemaining(
			remaining: .seconds(7),
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)

		#expect(quantizedRemaining == .seconds(10))
	}

	@Test
	func timeRemainingEstimatorQuantizesMinutesAboveThreshold() async throws {
		let quantizedRemaining = TimeRemainingEstimator.quantizedRemaining(
			remaining: .seconds(80),
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)

		#expect(quantizedRemaining == .seconds(60))
	}

	@Test
	func timeRemainingEstimatorThrottlesUpdates() async throws {
		var estimator = TimeRemainingEstimator(
			minimumUpdateInterval: .seconds(5),
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)
		let startInstant = ContinuousClock().now

		let firstUpdate = estimator.updatePresentation(
			remaining: .seconds(50),
			now: instant(afterSeconds: 0, from: startInstant)
		)
		#expect(firstUpdate == .seconds(50))

		let secondUpdate = estimator.updatePresentation(
			remaining: .seconds(40),
			now: instant(afterSeconds: 2, from: startInstant)
		)
		#expect(secondUpdate == nil)

		let thirdUpdate = estimator.updatePresentation(
			remaining: .seconds(40),
			now: instant(afterSeconds: 6, from: startInstant)
		)
		#expect(thirdUpdate == .seconds(40))
	}

	@Test
	func timeRemainingEstimatorDoesNotIncreasePresentedRemaining() async throws {
		var estimator = TimeRemainingEstimator(
			minimumUpdateInterval: .zero,
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)
		let startInstant = ContinuousClock().now

		let firstUpdate = estimator.updatePresentation(
			remaining: .seconds(40),
			now: instant(afterSeconds: 0, from: startInstant)
		)
		#expect(firstUpdate == .seconds(40))

		let increasedUpdate = estimator.updatePresentation(
			remaining: .seconds(50),
			now: instant(afterSeconds: 1, from: startInstant)
		)
		#expect(increasedUpdate == nil)

		let decreasedUpdate = estimator.updatePresentation(
			remaining: .seconds(30),
			now: instant(afterSeconds: 2, from: startInstant)
		)
		#expect(decreasedUpdate == .seconds(30))
	}

	@Test
	func timeRemainingEstimatorUpdatesWhenSecondsStyleChanges() async throws {
		var estimator = TimeRemainingEstimator(
			minimumUpdateInterval: .seconds(5),
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)
		let startInstant = ContinuousClock().now

		let firstUpdate = estimator.updatePresentation(
			remaining: .seconds(61),
			now: instant(afterSeconds: 0, from: startInstant)
		)
		#expect(firstUpdate == .seconds(60))

		let secondUpdate = estimator.updatePresentation(
			remaining: .seconds(49),
			now: instant(afterSeconds: 1, from: startInstant)
		)
		#expect(secondUpdate == .seconds(40))
	}

	@Test
	func timeRemainingEstimatorShowsMinutesAtThreshold() async throws {
		var estimator = TimeRemainingEstimator(
			minimumUpdateInterval: .zero,
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)
		let startInstant = ContinuousClock().now

		let update = estimator.updatePresentation(
			remaining: .seconds(59),
			now: instant(afterSeconds: 0, from: startInstant)
		)

		#expect(update == .seconds(50))
	}

	@Test
	func percentFormattedMarksPixelDimensionsAsApproximate() async throws {
		let originalSize = CGSize(width: 1920, height: 1080)
		let pixelDimensions = Dimensions.pixels(CGSize(width: 800, height: 450), originalSize: originalSize)
		#expect(pixelDimensions.percentFormatted.hasPrefix("~"))

		let percentDimensions = Dimensions.percent(0.5, originalSize: originalSize)
		#expect(!percentDimensions.percentFormatted.hasPrefix("~"))
	}

	@Test
	func settingOriginalSizePreservesPixelValue() {
		let dimensions = Dimensions.pixels(
			CGSize(width: 800, height: 450),
			originalSize: CGSize(width: 1920, height: 1080)
		)

		let croppedDimensions = dimensions.settingOriginalSize(CGSize(width: 1200, height: 675))

		#expect(croppedDimensions.pixels == CGSize(width: 800, height: 450))
		#expect(croppedDimensions.originalSize == CGSize(width: 1200, height: 675))
	}

	@Test
	func settingOriginalSizeFitsOversizedPixels() {
		let dimensions = Dimensions.pixels(
			CGSize(width: 800, height: 450),
			originalSize: CGSize(width: 1920, height: 1080)
		)

		let croppedDimensions = dimensions.settingOriginalSize(CGSize(width: 400, height: 400))

		#expect(croppedDimensions.pixels == CGSize(width: 400, height: 400))
		#expect(croppedDimensions.originalSize == CGSize(width: 400, height: 400))
	}

	@Test
	func settingOriginalSizeRecomputesPixelAspectForNewOriginalSize() {
		let dimensions = Dimensions.pixels(
			CGSize(width: 800, height: 450),
			originalSize: CGSize(width: 1920, height: 1080)
		)

		let croppedDimensions = dimensions.settingOriginalSize(CGSize(width: 1200, height: 1200))

		#expect(croppedDimensions.pixels == CGSize(width: 800, height: 800))
		#expect(croppedDimensions.originalSize == CGSize(width: 1200, height: 1200))
	}

	@Test
	func settingOriginalSizePreservesPercentValue() {
		let dimensions = Dimensions.percent(
			0.5,
			originalSize: CGSize(width: 1920, height: 1080)
		)

		let croppedDimensions = dimensions.settingOriginalSize(CGSize(width: 800, height: 600))

		#expect(croppedDimensions.pixels == CGSize(width: 400, height: 300))
		#expect(croppedDimensions.percent == 0.5)
	}

	@Test
	func uncroppedRenderSizeScalesUpByInverseOfCropFraction() {
		let conversion = conversion(
			dimensions: (width: 400, height: 300),
			crop: .init(x: 0.25, y: 0.25, width: 0.5, height: 0.75)
		)

		#expect(conversion.uncroppedRenderSize(forOutputSize: CGSize(width: 400, height: 300)) == CGSize(width: 800, height: 400))
	}

	@Test
	func uncroppedRenderSizeWithNoCropReturnsOutputSize() {
		let conversion = conversion(dimensions: (width: 400, height: 300))

		#expect(conversion.uncroppedRenderSize(forOutputSize: CGSize(width: 400, height: 300)) == CGSize(width: 400, height: 300))
	}

	@Test
	func appIntentOutputSettingsUseCropSizeForPercentDimensions() throws {
		var crop = Crop_AppEntity()
		crop.mode = .exact
		crop.x = 20
		crop.bottomLeftY = 30
		crop.width = 400
		crop.height = 300

		let intent = ConvertIntent()
		intent.dimensionsType = .percent
		intent.dimensionsPercent = 50
		intent.crop = crop

		let settings = try intent.outputSettings(metadataDimensions: .init(width: 1920, height: 1080))

		#expect(settings.dimensions?.width == 200)
		#expect(settings.dimensions?.height == 150)
	}

	@Test
	func appIntentOutputSettingsWithNoCropUsesFullDimensions() throws {
		let intent = ConvertIntent()
		intent.dimensionsType = .percent
		intent.dimensionsPercent = 50
		intent.crop = nil

		let settings = try intent.outputSettings(metadataDimensions: .init(width: 1920, height: 1080))

		#expect(settings.cropRect == nil)
		#expect(settings.dimensions?.width == 960)
		#expect(settings.dimensions?.height == 540)
	}

	@Test
	func appIntentOutputSettingsUseCropSizeForPixelDimensions() throws {
		var crop = Crop_AppEntity()
		crop.mode = .exact
		crop.x = 0
		crop.bottomLeftY = 0
		crop.width = 400
		crop.height = 200

		let intent = ConvertIntent()
		intent.dimensionsType = .pixels
		intent.dimensionsWidth = 200
		intent.crop = crop

		let settings = try intent.outputSettings(metadataDimensions: .init(width: 1920, height: 1080))

		#expect(settings.dimensions?.width == 200)
		#expect(settings.dimensions?.height == 100)
	}

	@Test
	func croppedSizeWithInitialCropReturnsOriginalDimensions() {
		let size = CropRect.initial.croppedSize(forDimensions: .init(width: 1920, height: 1080))

		#expect(size.width == 1920)
		#expect(size.height == 1080)
	}

	@Test
	func croppedSizeReturnsCropAreaInPixels() {
		let crop = CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.25)

		#expect(crop.croppedSize(forDimensions: .init(width: 1920, height: 1080)) == .init(width: 960, height: 270))
	}

	@Test
	func croppedSizeTruncatesFractionalPixels() {
		let crop = CropRect(x: 1.0 / 3.0, y: 1.0 / 3.0, width: 1.0 / 3.0, height: 1.0 / 3.0)
		let size = crop.croppedSize(forDimensions: .init(width: 100, height: 100))

		#expect(size.width == 33)
		#expect(size.height == 33)
	}

	@Test
	func cropMinimumSizeUsesOneHundredPixels() {
		let minSize = CropRect.minSize(videoSize: .init(width: 1920, height: 1080))

		#expect(minSize.width == 100.0 / 1920.0)
		#expect(minSize.height == 100.0 / 1080.0)
	}

	@Test
	func cropMinimumSizeIsCappedToSourceDimensions() {
		let minSize = CropRect.minSize(videoSize: .init(width: 50, height: 30))

		#expect(minSize.width == 1.0)
		#expect(minSize.height == 1.0)
	}

	@Test
	func symmetricCropDragOnTinySourceDoesNotTrap() {
		let crop = CropRect.initial
		let minSize = CropRect.minSize(videoSize: .init(width: 50, height: 50))
		let result = crop.applySymmetric(
			position: .topLeft,
			minSize: minSize,
			delta: .init(x: 0.1, y: 0.1)
		)

		#expect(result == crop)
	}

	@Test
	func symmetricCropDragWithAlreadyTooSmallCropDoesNotShrinkFurther() {
		let crop = CropRect(x: 0.4, y: 0.4, width: 0.02, height: 0.02)
		let minSize = crop.effectiveMinSizeForDrag(videoSize: .init(width: 1920, height: 1080))
		let result = crop.applySymmetric(
			position: .topLeft,
			minSize: minSize,
			delta: .init(x: 0.01, y: 0.01)
		)

		#expect(result == crop)
	}

	@Test
	func centeredAspectRatioCropOnTinySourceStaysInBounds() {
		let crop = CropRect.centeredFrom(
			aspectWidth: 16,
			aspectHeight: 9,
			forDimensions: .init(width: 50, height: 30)
		)

		#expect(crop == .initial)
	}

	@Test
	func aspectRatioCropInsideCurrentRectKeepsLongestSideWhenPossible() {
		let crop = CropRect(x: 0.3, y: 0.3, width: 0.4, height: 0.3)
		let result = crop.withAspectRatio(
			aspectWidth: 9,
			aspectHeight: 16,
			forDimensions: .init(width: 1000, height: 1000)
		)

		#expect(result == CropRect(x: 0.3875, y: 0.25, width: 0.225, height: 0.4))
	}

	@Test
	func uncroppedRenderSizeWithInitialCropReturnsOutputSize() {
		let conversion = conversion(
			dimensions: (width: 400, height: 300),
			crop: .initial
		)

		#expect(conversion.uncroppedRenderSize(forOutputSize: CGSize(width: 400, height: 300)) == CGSize(width: 400, height: 300))
	}

	@Test
	func uncroppedRenderSizeWithZeroWidthCropReturnsOutputSize() {
		let conversion = conversion(
			dimensions: (width: 400, height: 300),
			crop: .init(x: 0, y: 0, width: 0, height: 1)
		)

		#expect(conversion.uncroppedRenderSize(forOutputSize: CGSize(width: 400, height: 300)) == CGSize(width: 400, height: 300))
	}

	@Test
	func croppingImageThrowsForOutOfBoundsCrop() throws {
		let frame = try makeHorizontalSplitCGImage()
		let cropRect = CropRect(x: 1, y: 1, width: 0.5, height: 0.5)

		#expect(throws: CropRect.CropError.cropNotInBounds) {
			try cropRect.croppingImage(frame)
		}
	}

	@Test
	func croppingImageCropsToSelectedRegion() async throws {
		let frame = try makeHorizontalSplitCGImage()
		let cropRect = CropRect(x: 0.5, y: 0, width: 0.5, height: 1)
		let croppedFrame = try cropRect.croppingImage(frame)
		let data = try await GIFGenerator.convertOneFrame(
			frame: croppedFrame,
			dimensions: (width: 8, height: 16),
			quality: 0.8
		)

		#expect(croppedFrame.width == 8)
		#expect(croppedFrame.height == 16)
		#expect(try averageRedValue(gifData: data, frameIndex: 0) < 50)
	}

	@Test
	func writeToUniqueFileAddsIncrementingSuffixes() async throws {
		let directory = try URL.uniqueTemporaryDirectory()
		defer {
			try? directory.delete()
		}

		let data = Data("Test".utf8)
		let firstUrl = try data.writeToUniqueFile(in: directory, filename: "Sample", contentType: .gif)
		let secondUrl = try data.writeToUniqueFile(in: directory, filename: "Sample", contentType: .gif)

		#expect(firstUrl.lastPathComponent == "Sample.gif")
		#expect(secondUrl.lastPathComponent == "Sample 2.gif")
		#expect(firstUrl.exists)
		#expect(secondUrl.exists)
	}

	@Test
	func fileSizeEstimateCalibrationUsesLatestRatio() {
		var calibration = FileSizeEstimateCalibration()

		#expect(calibration.calibratedBytes(fromNaiveBytes: 120) == 120)

		calibration.update(naiveBytes: 100, betterBytes: 200)
		#expect(calibration.calibratedBytes(fromNaiveBytes: 150) == 300)

		calibration.update(naiveBytes: 200, betterBytes: 100)
		#expect(calibration.calibratedBytes(fromNaiveBytes: 50) == 25)
	}

	@Test
	func fileSizeEstimateCalibrationIgnoresNonPositiveValues() {
		var calibration = FileSizeEstimateCalibration()

		calibration.update(naiveBytes: 0, betterBytes: 100)
		#expect(calibration.calibratedBytes(fromNaiveBytes: 100) == 100)

		calibration.update(naiveBytes: 100, betterBytes: 0)
		#expect(calibration.calibratedBytes(fromNaiveBytes: 100) == 100)
	}

	@Test
	func fileSizeEstimateCalibrationIgnoresNonFiniteValues() {
		var calibration = FileSizeEstimateCalibration()

		calibration.update(naiveBytes: .infinity, betterBytes: 100)
		#expect(calibration.calibratedBytes(fromNaiveBytes: 100) == 100)

		calibration.update(naiveBytes: 100, betterBytes: .infinity)
		#expect(calibration.calibratedBytes(fromNaiveBytes: 100) == 100)
	}

	@Test
	func loopDelayOffsetOnlyAppliesWhenGifLoops() {
		let neverOffset: Double = Gifski.Loop.never.isLooping ? 0.4 : 0
		let foreverOffset: Double = Gifski.Loop.forever.isLooping ? 0.4 : 0
		let countOffset: Double = Gifski.Loop.count(3).isLooping ? 0.4 : 0

		#expect(neverOffset == 0)
		#expect(foreverOffset == 0.4)
		#expect(countOffset == 0.4)
	}

	@Test
	func gifDurationUsesTimeRangeAndBounceSetting() {
		// GIF conversion uses bounced duration, while MP4 export asks for the source direction only.
		let bouncing = conversion(timeRange: 1...3, bounce: true)

		#expect(bouncing.gifDuration(assetTimeRange: nil) == .seconds(4))
		#expect(bouncing.gifDuration(assetTimeRange: nil, withBounce: false) == .seconds(2))

		let nonBouncing = conversion(timeRange: 1...3, bounce: false)

		#expect(nonBouncing.gifDuration(assetTimeRange: nil) == .seconds(2))
	}

	@Test
	func gifDurationFallsBackToAssetTimeRange() {
		// Immediate convert/export can rely on the player-reported asset range before the user has trimmed.
		let conversion = conversion()
		let assetTimeRange = CMTimeRange(
			start: .init(seconds: 2, preferredTimescale: .video),
			end: .init(seconds: 7, preferredTimescale: .video)
		)

		#expect(conversion.gifDuration(assetTimeRange: assetTimeRange) == .seconds(5))
	}

	@Test
	func closedRangeTranslationScalesBetweenTimelines() {
		#expect((2.0...4.0).translated(from: 0...10, to: 0...5) == 1...2)
		#expect((0.0...5.0).translated(from: 0...7.5, to: 10...25) == 10...20)
		#expect((12.0...16.0).translated(from: 10...20, to: 100...200) == 120...160)
	}

	@Test
	func closedRangeTranslationClampsToTargetTimeline() {
		#expect((-1.0...12.0).translated(from: 0...10, to: 100...110) == 100...110)
		#expect((3.0...4.0).translated(from: 2...2, to: 10...20) == 10...10)
		// Partial upper-bound overflow: only the upper bound clips.
		#expect((2.0...8.0).translated(from: 0...6, to: 0...10) == (10.0 / 3)...10)
	}

	@Test
	func closedRangeTranslationPreservesIdentity() {
		#expect((2.0...8.0).translated(from: 0...10, to: 0...10) == 2...8)
	}

	@Test
	func closedRangeClampingBoundsClampsToRange() {
		#expect((-1.0...12.0).clampingBounds(to: 0...10) == 0...10)
		#expect((3.0...7.0).clampingBounds(to: 0...10) == 3...7)
		#expect((5.0...15.0).clampingBounds(to: 0...10) == 5...10)
	}

	@Test
	func cropRectConvertsFromRotatedSpaceToNaturalVideoSpace() {
		let conversion = conversion(
			crop: .init(
				x: 0.25,
				y: 0.125,
				width: 0.5,
				height: 0.75
			)
		)
		let cropRect = conversion.cropRectInNaturalSpace(
			naturalSize: .init(
				width: 1920,
				height: 1080
			),
			preferredTransform: .init(
				a: 0,
				b: 1,
				c: -1,
				d: 0,
				tx: 1080,
				ty: 0
			)
		)

		#expect(cropRect == .init(
			x: 240,
			y: 270,
			width: 1440,
			height: 540
		))
	}

	@Test
	func cropRectInNaturalSpaceKeepsIdentityTransformCoordinates() {
		let conversion = conversion(
			crop: .init(
				x: 0.1,
				y: 0.2,
				width: 0.3,
				height: 0.4
			)
		)
		let cropRect = conversion.cropRectInNaturalSpace(
			naturalSize: .init(
				width: 1000,
				height: 500
			),
			preferredTransform: .identity
		)

		#expect(cropRect == .init(
			x: 100,
			y: 100,
			width: 300,
			height: 200
		))
	}

	@Test
	func cropRectInNaturalSpaceUsesFullFrameWhenCropIsNil() {
		// Nil crop is the fast no-crop path, but geometry queries should still resolve it as the full frame.
		let conversion = conversion()
		let cropRect = conversion.cropRectInNaturalSpace(
			naturalSize: .init(
				width: 1920,
				height: 1080
			),
			preferredTransform: .identity
		)

		#expect(cropRect == .init(
			x: 0,
			y: 0,
			width: 1920,
			height: 1080
		))
	}

	@Test
	func `deinit during encode cleanup does not crash`() async throws {
		var gifski: Gifski? = try Gifski(
			dimensions: (width: 1, height: 1),
			quality: 1,
			loop: .never,
			fast: true
		)
		let gifskiReference: LockedGifskiReference
		var wrapper: GifskiWrapper?
		weak var weakGifski: Gifski?

		do {
			let concreteGifski = try #require(gifski)
			gifskiReference = LockedGifskiReference(concreteGifski)
			weakGifski = concreteGifski
			wrapper = try #require(Mirror(reflecting: concreteGifski).descendant("wrapper", "some") as? GifskiWrapper)
		}
		weak let weakWrapper = wrapper

		wrapper?.setWriteCallback { _, _ in
			gifskiReference.gifski = nil
			return 0
		}

		gifski = nil

		for frameNumber in 0..<20 {
			guard weakGifski != nil else {
				break
			}

			try wrapper?.addFrame(
				pixelFormat: .rgba,
				frameNumber: frameNumber,
				width: 1,
				height: 1,
				bytesPerRow: 4,
				pixels: [UInt8(frameNumber), 0, 0, 255],
				presentationTimestamp: Double(frameNumber) / 10
			)
		}
		wrapper = nil

		var didFinishCleanup = false

		for _ in 0..<40 {
			if weakGifski == nil, weakWrapper == nil {
				didFinishCleanup = true
				break
			}

			try await Task.sleep(for: .milliseconds(50))
		}

		#expect(didFinishCleanup)
	}
}

private final class LockedGifskiReference: @unchecked Sendable {
	private let lock = NSLock()
	private var _gifski: Gifski?

	init(_ gifski: Gifski) {
		self._gifski = gifski
	}

	var gifski: Gifski? {
		get {
			lock.lock()
			defer {
				lock.unlock()
			}

			return _gifski
		}
		set {
			lock.lock()
			defer {
				lock.unlock()
			}

			_gifski = newValue
		}
	}
}
