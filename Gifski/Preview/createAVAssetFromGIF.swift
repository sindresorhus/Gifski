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
func createAVAssetFromGIF(imageSource: CGImageSource, settings: SettingsForFullPreview, onProgress: (Double) -> Void) async throws -> TemporaryAVURLAsset {
	let numberOfImages = CGImageSourceGetCount(imageSource)
	guard numberOfImages > 0
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
	} else if let inputFrameRate = try? await settings.conversion.asset.frameRate {
		frameRate = CMTimeScale(inputFrameRate)
	} else {
		frameRate = CMTimeScale(30.0)
	}


	let dataReadyStream = AsyncStream { continuation in
		writerInput.requestMediaDataWhenReady(on: dispatchQueue) {
			continuation.yield()
		}
	}
	var progressThreshold = 0.05
	for await _ in dataReadyStream {
		while writerInput.isReadyForMoreMediaData && frameIndex < numberOfImages {
			let progress = Double(frameIndex) / Double(numberOfImages)
			if progress > progressThreshold {
				onProgress(progress)
				progressThreshold = progress + 0.05
			}

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
		if frameIndex >= numberOfImages {
			break
		}
	}

	writerInput.markAsFinished()
	await withCheckedContinuation { continuation in
		assetWriter.finishWriting {
			continuation.resume()
		}
	}
	return TemporaryAVURLAsset(url: tempPath)
}


enum CreateAVAssetError: Error {
	case failedToCreateImageData
	case failedToCreateImage
	case failedToCreateAssetWriter
	case cannotAddWriterInput
	case noImages
}
final class TemporaryAVURLAsset: AVURLAsset, @unchecked Sendable {
	deinit {
		try? FileManager.default.removeItem(at: self.url)
	}
}
