//
//  PreviewVideoCompositor.swift
//  Gifski
//
//  Created by Michael Mulet on 4/21/25.
//

import Foundation
import AVFoundation
import CoreImage

/**
 A video compositor to composite the preview over the original video. This is called by the AVPlayer on redraws. What it draws depends on fullPreviewStatus: if we are generating or don't have a fullPreview, we will generate a GIF of the current frame on the fly. If we have a full preview then it will just composite the full preview with the frame in most cases.
 */
final class PreviewVideoCompositor: NSObject, AVVideoCompositing {
	@MainActor
	var shouldShowPreview = false
	@MainActor
	var fullPreviewStatus: FullPreviewGenerationEvent.Status?
	@MainActor
	var previewCheckerboardParams: PreviewRenderer.PreviewCheckerboardParameters = .init(isDarkMode: true, videoBounds: .zero)
	/**
	 see [OutputCache](PreviewVideoCompositor.OutputCache) on why we need this
	 */
	private var outputCache = OutputCache()
	func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
		guard let outputFrame = asyncVideoCompositionRequest.renderContext.newPixelBuffer(),
			  let originalFrame = asyncVideoCompositionRequest.sourceFrame(byTrackID: .originalVideoTrack)
		else {
			asyncVideoCompositionRequest.finish(with: PreviewVideoCompositorError.failedToGetVideoFrame)
			return
		}
		originalFrame.propagateAttachments(to: outputFrame)

		let fullPreviewFrame = asyncVideoCompositionRequest.sourceFrame(byTrackID: .fullPreviewVideoTrack)
		Task.detached(priority: .userInitiated) {
			do {
				try await self.render(fullPreviewFrame: fullPreviewFrame, originalFrame: originalFrame, outputFrame: outputFrame, compositionTime: asyncVideoCompositionRequest.compositionTime)
				asyncVideoCompositionRequest.finish(
					withComposedVideoFrame: outputFrame
				)
			} catch {
				assertionFailure()
				try? self.renderOriginal(from: originalFrame, to: outputFrame)
				asyncVideoCompositionRequest.finish(
					withComposedVideoFrame: outputFrame
				)
			}
		}
	}

	private func render(
		fullPreviewFrame: CVPixelBuffer?,
		originalFrame: CVPixelBuffer,
		outputFrame: CVPixelBuffer,
		compositionTime reportedCompositionTime: CMTime
	) async throws {
		let fullPreviewStatus = await fullPreviewStatus
		let compositionTime = OriginalCompositionTime(reportedCompositionTime: reportedCompositionTime, speed: fullPreviewStatus?.settings.speed)

		guard await shouldShowPreview else {
			if fullPreviewStatus.isGenerating {
				await MainActor.run {
					lastGenerateTimeWhileNotShowingPreview = compositionTime
				}
			}
			try renderOriginal(
				from: originalFrame,
				to: outputFrame
			)
			return
		}

		guard let fullPreviewStatus else {
			if try await outputCache.restoreFromCache(to: outputFrame, at: compositionTime, with: fullPreviewStatus?.settings) {
				return
			}

			try renderOriginal(
				from: originalFrame,
				to: outputFrame
			)
			return
		}
		guard fullPreviewStatus.ready else {
			try await convertToGIFAndRender(originalFrame: originalFrame, outputFrame: outputFrame, settings: fullPreviewStatus.settings, compositionTime: compositionTime)
			return
		}
		// Need this for the case where the player is paused, not showing the preview, then the user presses the show preview button. Due to a bug in AVPlayer it won't update the PreviewFrame (it's content wil exist (not nil) bit will bel be old and out of date), so we need to regenerate the content rather than use the fullPreviewFrame
		if let lastGenerateTimeWhileNotShowingPreview = await lastGenerateTimeWhileNotShowingPreview,
		   lastGenerateTimeWhileNotShowingPreview == compositionTime {
			try await convertToGIFAndRender(originalFrame: originalFrame, outputFrame: outputFrame, settings: fullPreviewStatus.settings, compositionTime: compositionTime)
			return
		}
		guard let fullPreviewFrame else {
			if let preBakedFrame = fullPreviewStatus.preBaked?.getPreBakedFrame(forTime: compositionTime)  {
				try await PreviewRenderer.renderPreview(previewFrame: preBakedFrame, outputFrame: outputFrame, previewCheckerboardParams: previewCheckerboardParams)
				return
			}
			try await convertToGIFAndRender(originalFrame: originalFrame, outputFrame: outputFrame, settings: fullPreviewStatus.settings, compositionTime: compositionTime)
			return
		}
		if try await outputCache.restoreFromCache(to: outputFrame, at: compositionTime, with: fullPreviewStatus.settings) {
			return
		}

		try await PreviewRenderer.renderPreview(previewFrame: fullPreviewFrame, outputFrame: outputFrame, previewCheckerboardParams: previewCheckerboardParams)
		return
	}
	private func convertToGIFAndRender(originalFrame: CVPixelBuffer, outputFrame: CVPixelBuffer, settings: SettingsForFullPreview, compositionTime: OriginalCompositionTime) async throws {
		let frame = try await convertFrameToGIF(videoFrame: originalFrame, settings: settings)
		try await PreviewRenderer.renderPreview(previewFrame: frame, outputFrame: outputFrame, previewCheckerboardParams: previewCheckerboardParams)
		try await outputCache.cacheBuffer(outputFrame, at: compositionTime, with: settings)
	}

	private func renderOriginal(
		from videoFrame: CVPixelBuffer,
		to outputFrame: CVPixelBuffer,
	) throws {
		try videoFrame.copy(to: outputFrame)
	}
	private func convertFrameToGIF(
		videoFrame: CVPixelBuffer,
		settings: SettingsForFullPreview
	) async throws -> CGImage  {
		//  Not the fastest way to convert CVPixelBuffer to image, but the runtime of `GIFGenerator.convertOneFrame` is so much larger that optimizing this would be a waste
		let ciImage = CIImage(cvPixelBuffer: videoFrame)
		let ciContext = CIContext()
		guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
		else {
			throw PreviewVideoCompositorError.failedToCreateCGContext
		}
		guard let croppedImage = settings.conversion.croppedImage(image: cgImage) else {
			throw GIFGenerator.Error.cropNotInBounds
		}
		let data = try await GIFGenerator.convertOneFrame(
			frame: croppedImage,
			dimensions: settings.conversion.croppedOutputDimensions,
			quality: max(0.1, settings.conversion.quality),
			fast: true
		)
		guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
			  let gifFrame = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
			throw PreviewVideoCompositorError.failedToConvertFramePreviewGif
		}
		return gifFrame
	}
	/**
	 There is a bug in AVplayer described like this: If it is paused and you update the the fullPreviewTrack (a full Preview is complete) the effect of the update don't take place until the user presses play or seeks. It will still get startRequests but the value of the fullPreviewFrame will be invalid (an old fullPreview). So what we need to do is cache the frame and keep it in memory and continue to show this one frame as long as the time matches up.  If we are not previewing at the time we have to save the lastGenerationTimeWhileNotShowing the preview or create this preview later. The only alternative is to reset the AVplayerItem which causes a ghastly flash on the screen.
	 */
	@MainActor
	private var lastGenerateTimeWhileNotShowingPreview: OriginalCompositionTime?
	/**
	 Need this cache to fix a bug in AVPlayer, see  [lastGenerateTimeWhileNotShowingPreview](PreviewVideoCompositor.lastGenerateTimeWhileNotShowingPreview) for the description
	 */
	private actor OutputCache {
		private var cache: CVPixelBuffer?

		private struct Latest {
			let writeTime: OriginalCompositionTime
			let settings: SettingsForFullPreview
		}

		private var latest: Latest?

		/**
		 If settings is nil, match with any settings, returns true if we restored from cache, false if we couldn't and throws an error on error
		 */
		func restoreFromCache(to buffer: CVPixelBuffer, at time: OriginalCompositionTime, with settings: SettingsForFullPreview?) throws -> Bool {
			guard let latest,
				  latest.writeTime == time,
				  let cache else {
				return false
			}
			guard let settings else {
				try cache.copy(to: buffer)
				return true
			}

			guard latest.settings.areTheSameBesidesTimeRange(settings) else {
				return false
			}
			try cache.copy(to: buffer)
			return true
		}
		func cacheBuffer(_ buffer: CVPixelBuffer, at time: OriginalCompositionTime, with settings: SettingsForFullPreview) throws {
			if let cache {
				try buffer.copy(to: cache)
				latest = Latest(writeTime: time, settings: settings)
				return
			}
			guard let copyable = buffer.makeCompatibleBuffer() else {
				return
			}
			try buffer.copy(to: copyable)
			cache = copyable
			latest = Latest(writeTime: time, settings: settings)
		}
	}
	enum PreviewVideoCompositorError: Error {
		case unreachable
		case failedToGetFullGifFrame
		case failedToGetVideoFrame
		case failedToGetRenderContext
		case failedToGetOutputBuffer
		case failedToConvertFramePreviewGif
		case failedToCreateCGContext
	}
	// swiftlint:disable:next discouraged_optional_collection
	let sourcePixelBufferAttributes: [String: any Sendable]? = [
		kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
	]
	let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
		kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
	]
	func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
		 // no-op
	}

	/**
	 Time that been scaled. The composition will speed up or slowdown the time.   for example if the player is at 2x speed. This struct it takes the reported time of 0.5 and multiplies it by 2, to get 1 second the original  time in the composition.
	 */
	struct OriginalCompositionTime: Equatable {
		let seconds: Double
		init(reportedCompositionTime: CMTime, speed: Double?) {
			seconds = reportedCompositionTime.seconds * (speed ?? 1)
		}
	}
}

extension CMPersistentTrackID {
	static let originalVideoTrack: CMPersistentTrackID = 434
	static let fullPreviewVideoTrack: CMPersistentTrackID = 435
}
