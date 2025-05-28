//
//  createAVAssetFromGIF.swift
//  Gifski
//
//  Created by Michael Mulet on 4/22/25.
//

import Foundation
import AVKit

/**
 Convert a GIF to an AVAAsset
 */
func createAVAssetFromGIF(imageSource: CGImageSource, settings: SettingsForFullPreview, onProgress: @escaping (Double) async -> Void) async throws -> TemporaryAVURLAsset {
	let numberOfImages = imageSource.count
	guard numberOfImages > 0,
		  let firstCGImage = imageSource.createImage(atIndex: 0)
	else {
		throw CreateAVAssetError.noImages
	}

	let tempPath = FileManager.default.temporaryDirectory.appending(component: "\(UUID()).mov")
	guard let assetWriter = try? AVAssetWriter(outputURL: tempPath, fileType: .mov) else {
		throw CreateAVAssetError.failedToCreateAssetWriter
	}

	let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
		AVVideoCodecKey: AVVideoCodecType.h264,
		AVVideoWidthKey: firstCGImage.width,
		AVVideoHeightKey: firstCGImage.height,
		AVVideoColorPropertiesKey: [
			// setup the video color properties to match the output GIF. By default GIFs use sRGB colorspace (with a gamma value of 2.2), while the .h264  codec uses Rec. 709 color space (with a gamma value of 2.4). This mismatch causes the output to appear "brighter" than it should be, so we have to set the `AVVideoTransferFunctionKey` to `AVVideoTransferFunction_IEC_sRGB` to use sRGB. See [1. Rec. 709 wikipedia page](https://web.archive.org/web/20250430035611/https://en.wikipedia.org/wiki/Rec._709) especially the `Comparison to sRGB` section on the bottom or [2. the page that wikipedia cites](https://web.archive.org/web/20250416122435/https://www.image-engineering.de/library/technotes/714-color-spaces-rec-709-vs-srgb).
			AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
			//  When using `AVVideoColorPropertiesKey` you *must* specify all three keys (or else it will raise an exception), so we set `AVVideoColorPrimariesKey` and `AVVideoYCbCrMatrixKey` to their default values for the 709 colorspace because sRGB and 709 "share the same primary chromaticities, but they have different transfer functions"^2.
			AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
			AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
		]
	])

	writerInput.expectsMediaDataInRealTime = false
	let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
		assetWriterInput: writerInput,
		sourcePixelBufferAttributes: [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
			kCVPixelBufferWidthKey as String: firstCGImage.width,
			kCVPixelBufferHeightKey as String: firstCGImage.height,
			kCVPixelBufferCGImageCompatibilityKey as String: true,
			kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
		]
	)
	guard assetWriter.canAdd(writerInput) else {
		throw CreateAVAssetError.cannotAddWriterInput
	}
	assetWriter.add(writerInput)

	guard assetWriter.startWriting() else {
		throw CreateAVAssetError.failedToStartWriting
	}
	assetWriter.startSession(atSourceTime: .zero)

	var frameIndex = 0

	let frameRate: CMTimeScale = await {
		if let settingFrameRate = settings.conversion.frameRate {
			return CMTimeScale(settingFrameRate)
		}
		if let inputFrameRate = try? await settings.conversion.asset.frameRate {
			return CMTimeScale(inputFrameRate)
		}
		return CMTimeScale(30.0)
	}()


	let dispatchQueue = DispatchQueue(label: "com.gifski.assetWriterQueue")
	let sendableImageSource = SendableWrapper(imageSource)
	let sendableWriterInput = SendableWrapper(writerInput)
	let sendablePixelBufferAdaptor = SendableWrapper(pixelBufferAdaptor)

	try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
		writerInput.requestMediaDataWhenReady(on: dispatchQueue) {
			do {
				var progressThreshold = 0.05
				while sendableWriterInput.value.isReadyForMoreMediaData && frameIndex < numberOfImages {
					try Task.checkCancellation()
					let progress = Double(frameIndex) / Double(numberOfImages)
					if progress > progressThreshold {
						Task {
							await onProgress(progress)
						}
						progressThreshold = progress + 0.05
					}
					defer {
						frameIndex += 1
					}
					guard let cgImage = sendableImageSource.value.createImage(atIndex: frameIndex) else {
						throw CreateAVAssetError.failedToCreateImage
					}
					guard let pixelBufferPool = sendablePixelBufferAdaptor.value.pixelBufferPool else {
						throw CreateAVAssetError.failedToCreatePixelBufferPool
					}
					let pixelBuffer = try createPixelBuffer(from: cgImage, using: pixelBufferPool)

					let presentationTime = CMTime(
						value: CMTimeValue(frameIndex),
						timescale: frameRate
					)
					guard sendablePixelBufferAdaptor.value.append(pixelBuffer, withPresentationTime: presentationTime) else {
						throw CreateAVAssetError.cannotAppendNewImage
					}
				}
				if frameIndex >= numberOfImages {
					sendableWriterInput.value.markAsFinished()
					continuation.resume()
				}
			} catch {
				sendableWriterInput.value.markAsFinished()
				continuation.resume(throwing: error)
			}
		}
	}
	await assetWriter.finishWriting()
	guard assetWriter.status != .failed else {
		throw CreateAVAssetError.failedToWrite
	}
	return TemporaryAVURLAsset(tempFileURL: tempPath)
}

private func createPixelBuffer(from cgImage: CGImage, using pool: CVPixelBufferPool) throws -> CVPixelBuffer {
	let pixelBuffer = try pool.createPixelBuffer()

	return try pixelBuffer.withLockedPlanes { planes -> CVPixelBuffer in
		guard planes.count == 1,
			  let plane = planes.first else {
			throw CreateAVAssetError.poolCreatedInvalidPixelBuffer
		}
		guard let context = CGContext(
			data: plane.base,
			width: cgImage.width,
			height: cgImage.height,
			bitsPerComponent: 8,
			bytesPerRow: plane.bytesPerRow,
			space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
		) else {
			throw CreateAVAssetError.cgContextCreationFailed
		}
		context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
		return pixelBuffer
	}
}


enum CreateAVAssetError: Error {
	case failedToStartWriting
	case failedToCreateImageData
	case failedToCreateImage
	case failedToCreatePixelBufferPool
	case failedToCreateAssetWriter
	case failedToWrite
	case cannotAddWriterInput
	case cannotAppendNewImage
	case noImages
	case poolCreatedInvalidPixelBuffer
	case cgContextCreationFailed
}

final class TemporaryAVURLAsset: AVURLAsset, @unchecked Sendable {
	init(tempFileURL: URL) {
		super.init(url: tempFileURL, options: nil)
		TempFileTracker.shared.register(tempFileURL)
	}

	deinit {
		TempFileTracker.shared.unregister(self.url)
		try? FileManager.default.removeItem(at: self.url)
	}
}
