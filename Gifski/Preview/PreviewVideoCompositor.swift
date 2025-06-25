import Foundation
import AVFoundation
import CoreImage

/**
A video compositor to composite the preview over the original video. This is called by the `AVPlayer` on redraws. What it draws depends on the state: if we are generating or don't have a full preview, we will generate a GIF of the current frame on the fly. If we have a full preview then it will just composite the full preview with the frame in most cases.
*/
final class PreviewVideoCompositor: NSObject, AVVideoCompositing {
	enum Error: Swift.Error {
		case failedToGetVideoFrame
	}

	@MainActor
	private var state = State()

	/**
	- Returns: True if the state needed an update and you should redraw, false if there is no change.
	*/
	@MainActor
	func updateState(
		state: State
	) -> Bool {
		if self.state ~= state {
			return false
		}

		self.state = state

		return true
	}

	func startRequest(_ unwrappedRequest: AVAsynchronousVideoCompositionRequest) {
		// Safe to wrap it like this because we never ever use the wrapped value in this thread anymore.
		struct WrappedRequest: @unchecked Sendable {
			let value: AVAsynchronousVideoCompositionRequest
		}

		let wrapped = WrappedRequest(value: unwrappedRequest)

		Task.detached(priority: .userInitiated) {
			let asyncVideoCompositionRequest = wrapped.value
			let compositionTime = asyncVideoCompositionRequest.compositionTime

			guard
				let outputFrame = asyncVideoCompositionRequest.renderContext.newPixelBuffer(),
				let sourceTrackID = asyncVideoCompositionRequest.sourceTrackIDs.first,
				let originalFrame = asyncVideoCompositionRequest.sourceFrame(byTrackID: sourceTrackID.int32Value)
			else {
				asyncVideoCompositionRequest.finish(with: Error.failedToGetVideoFrame)
				return
			}

			do {
				try await self.state.render(
					originalFrame: originalFrame,
					outputFrame: outputFrame,
					compositionTime: compositionTime
				)

				asyncVideoCompositionRequest.finish(withComposedVideoFrame: outputFrame)
			} catch {
				assertionFailure()

				try? await PreviewRenderer.shared.renderOriginal(
					from: originalFrame.previewSendable,
					to: outputFrame.previewSendable
				)

				asyncVideoCompositionRequest.finish(withComposedVideoFrame: outputFrame)
			}
		}
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
}

extension PreviewVideoCompositor {
	struct State: Equatable {
		private let shouldShowPreview: Bool
		private let fullPreviewState: FullPreviewGenerationEvent
		private let previewCheckerboardParams: CompositePreviewFragmentUniforms

		init() {
			self.shouldShowPreview = false
			self.fullPreviewState = .initialState
			self.previewCheckerboardParams = .init()
		}

		init(
			shouldShowPreview: Bool,
			fullPreviewState: FullPreviewGenerationEvent,
			previewCheckerboardParams: CompositePreviewFragmentUniforms
		) {
			self.shouldShowPreview = shouldShowPreview
			self.fullPreviewState = fullPreviewState
			self.previewCheckerboardParams = previewCheckerboardParams
		}

		func render(
			originalFrame: CVPixelBuffer,
			outputFrame: CVPixelBuffer,
			compositionTime: CMTime
		) async throws {
			guard
				shouldShowPreview,
				let previewFrame = try await fullPreviewState.getPreviewFrame(
					originalFrame: originalFrame,
					compositionTime: compositionTime
				)
			else {
				try await PreviewRenderer.shared.renderOriginal(
					from: originalFrame.previewSendable,
					to: outputFrame.previewSendable
				)

				return
			}

			try await PreviewRenderer.shared.renderPreview(
				previewFrame: previewFrame,
				outputFrame: outputFrame.previewSendable,
				fragmentUniforms: previewCheckerboardParams
			)
		}
	}
}

extension PreviewVideoCompositor.State: PreviewComparable {
	static func ~= (lhs: Self, rhs: Self) -> Bool {
		guard
			lhs.shouldShowPreview == rhs.shouldShowPreview,
			lhs.previewCheckerboardParams == rhs.previewCheckerboardParams
		else {
			return false
		}

		return lhs.fullPreviewState ~= rhs.fullPreviewState
	}
}
