//
//  createVideoFromSetting.swift
//  Gifski
//
//  Created by Michael Mulet on 4/17/25.
//

import Foundation
import AVFoundation

func createPreviewVideoFromSettings(_ settings: SettingsForPreview) async throws -> URL {
	let data = try await GIFGenerator.run(settings.conversion) { _ in
		/**
		 No-op
		 */
	}
	try Task.checkCancellation()
	return try await createAVAssetFromGif(data: data, settings: settings)
}

/**
 We have to add about 0.1 seconds to the upper range so that it avoids the bug where it will not show the preview when increasing the trim  to the right
 */
func padEndTime(_ settings: SettingsForPreview) async throws -> SettingsForPreview {
	let assetDuration = try await settings.conversion.asset.load(.duration)
	var newConversion = settings.conversion

	newConversion.timeRange = { () -> ClosedRange<Double>? in
		guard let timeRange = settings.conversion.timeRange else {
			return nil
		}
		let upperBound = min(assetDuration.seconds, timeRange.upperBound + 0.1)
		return timeRange.lowerBound...(upperBound)
	}()

	return newConversion.settingsForPreview
}

private func createAVAssetFromGif(data: Data, settings: SettingsForPreview) async throws -> URL {
	guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
		throw CreateAVAssetError.failedToCreateImageData
	}

	let numberOfImagesCount = CGImageSourceGetCount(imageSource)
	guard numberOfImagesCount > 0
	else {
		throw CreateAVAssetError.noImages
	}
	guard let firstCGImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
		throw CreateAVAssetError.failedToCreateImage
	}
	let tempPath = FileManager.default.temporaryDirectory.appending(component: "\(UUID()).mov")
	guard let assetWriter = try? AVAssetWriter(outputURL: tempPath, fileType: .mov) else {
		throw CreateAVAssetError.failedToCreateAssetWriter
	}

	let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
		AVVideoCodecKey: AVVideoCodecType.h264,
		AVVideoWidthKey: firstCGImage.width,
		AVVideoHeightKey: firstCGImage.height
	])
	writerInput.expectsMediaDataInRealTime = false
	let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
		assetWriterInput: writerInput,
		sourcePixelBufferAttributes: [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
			kCVPixelBufferWidthKey as String: firstCGImage.width,
			kCVPixelBufferHeightKey as String: firstCGImage.height
		]
	)
	guard assetWriter.canAdd(writerInput) else {
		throw CreateAVAssetError.cannotAddWriterInput
	}
	assetWriter.add(writerInput)

	assetWriter.startWriting()
	assetWriter.startSession(atSourceTime: .zero)

	let dispatchQueue = DispatchQueue(label: "com.gifski.assetWriterQueue")
	var frameIndex = 0

	let frameRate: CMTimeScale
	if let settingFrameRate = settings.conversion.frameRate {
		frameRate = CMTimeScale(settingFrameRate)
	} else if let inputFrameRaate = try? await settings.conversion.asset.frameRate {
		frameRate = CMTimeScale(inputFrameRaate)
	} else {
		frameRate = CMTimeScale(30.0)
	}


	let dataReadyStream = AsyncStream { continuation in
		writerInput.requestMediaDataWhenReady(on: dispatchQueue) {
			continuation.yield()
		}
	}
	for await _ in dataReadyStream {
		while writerInput.isReadyForMoreMediaData && frameIndex < numberOfImagesCount {
			try Task.checkCancellation()

			defer {
				frameIndex += 1
			}
			guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, frameIndex, nil) else {
				continue
			}
			guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
				continue
			}
			var pixelBuffer: CVPixelBuffer?
			guard CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer) == kCVReturnSuccess,
				  let pixelBuffer else {
				continue
			}
			CVPixelBufferLockBaseAddress(pixelBuffer, [])
			defer {
				CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
			}

			guard let context = CGContext(
				data: CVPixelBufferGetBaseAddress(pixelBuffer),
				width: cgImage.width,
				height: cgImage.height,
				bitsPerComponent: 8,
				bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
			) else {
				continue
			}
			context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
			let presentationTime = CMTime(
				value: CMTimeValue(frameIndex),
				timescale: frameRate
			)
			pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
		}
		if frameIndex >= numberOfImagesCount {
			break
		}
	}

	writerInput.markAsFinished()
	await withCheckedContinuation { continuation in
		assetWriter.finishWriting {
			continuation.resume()
		}
	}
	return tempPath
}


enum CreateAVAssetError: Error {
	case failedToCreateImageData
	case failedToCreateImage
	case failedToCreateAssetWriter
	case cannotAddWriterInput
	case noImages
}

struct SettingsForPreview: Equatable {
	let conversion: GIFGenerator.Conversion
	init(conversion: GIFGenerator.Conversion) {
		var newConversion = conversion
		newConversion.loop = .never
		newConversion.bounce = false
		self.conversion = newConversion
	}

	func areTheSameBesidesTrim(_ settings: Self) -> Bool {
		var copyOld = self.conversion
		copyOld.timeRange = nil

		var copyNew = settings.conversion
		copyNew.timeRange = nil

		return copyNew == copyOld
	}

	func trimRangeContainsTrimeRange(
		of newSettings: Self,
	) -> Bool {
		guard let oldTimeRange = self.conversion.timeRange else {
			/**
			 nil means the entire duration, so all sets are subset of the range
			 */
			return true
		}
		guard let newTimeRange = newSettings.conversion.timeRange else {
			/**
			 old is not full, but new is full, thus it is not a subset
			 */
			return false
		}
		return oldTimeRange.contains(newTimeRange)
	}
}

extension GIFGenerator.Conversion {
	var settingsForPreview: SettingsForPreview {
		SettingsForPreview(conversion: self)
	}
}
