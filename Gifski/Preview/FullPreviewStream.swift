import Foundation
import AVFoundation
import Compression

actor FullPreviewStream {
	private let stateStreamContinuation: AsyncStream<FullPreviewGenerationEvent>.Continuation
	private var state = FullPreviewGenerationEvent.initialState

	/**
	The current cancellable task that may be creating a new full preview. There will only be one `generationTask` at a time. The old one will be canceled before starting a new one.
	*/
	private var generationTask: Task<Void, Never>?

	/**
	Incremented on every new request.
	*/
	private var automaticRequestID = 0

	private func newID() -> Int {
		automaticRequestID += 1
		return automaticRequestID
	}

	let eventStream: AsyncStream<FullPreviewGenerationEvent>

	init() {
		// The output stream. This is a stream of `FullPreviewGenerationEvents`.
		(self.eventStream, self.stateStreamContinuation) = AsyncStream<FullPreviewGenerationEvent>.makeStream(bufferingPolicy: .bufferingNewest(100))

		stateStreamContinuation.onTermination = { [weak self] _ in
			guard let self else {
				return
			}

			Task { [weak self] in
				await self?.generationTask?.cancel()
			}
		}
	}

	deinit {
		generationTask?.cancel()
		stateStreamContinuation.finish()
	}

	/**
	Request a new full preview.

	Returns when the generation has *started* not when it finishes. Monitor the `eventStream` for the status of the generation.
	*/
	func requestNewFullPreview(
		asset: sending AVAsset,
		settingsEvent newSettings: SettingsForFullPreview
	) async {
		let requestID = newID()

		requestID.p("starting new settings")

		guard state.isNecessaryToCreateNewFullPreview(newSettings: newSettings, newRequestID: requestID) else {
			// Not necessary to create a new full preview since there is no state change.
			return
		}

		requestID.p("Generating")

		if
			let generationTask,
			!generationTask.isCancelled
		{
			requestID.p("canceling")
			generationTask.cancel()
			_ = await generationTask.result
			requestID.p("canceled old")
		}

		generationTask = .detached(priority: .medium) {
			do {
				await self.updatePreview(
					newPreviewState: .generating(
						settings: newSettings,
						progress: 0,
						requestID: requestID
					)
				)

				let fullPreviewTask = Self.convertToFullPreview(asset: asset, newSettings: newSettings)

				await withTaskCancellationHandler {
					for await progress in fullPreviewTask.progress {
						await self.updatePreview(
							newPreviewState: .generating(
								settings: newSettings,
								progress: progress,
								requestID: requestID
							)
						)
					}
				} onCancel: {
					fullPreviewTask.cancel()
				}

				try Task.checkCancellation()
				let textures = try await fullPreviewTask.value

				try Task.checkCancellation()
				requestID.p("success")

				await self.updatePreview(newPreviewState: .ready(settings: newSettings, gifData: textures, requestID: requestID))
			} catch {
				if Task.isCancelled || error.isCancelled {
					requestID.p("I was cancelled")
					return
				}

				await self.updatePreview(newPreviewState: .empty(error: error.localizedDescription, requestID: requestID))
			}
		}
	}

	static func convertToFullPreview(
		asset: AVAsset,
		newSettings: SettingsForFullPreview
	) -> ProgressableTask<Double, [SendableTexture?]> {
		GIFGenerator.runProgressable(newSettings.conversion.toConversion(asset: asset))
			.then(progressWeight: 0.67) {
				try await PreviewRenderer.shared.convertAnimatedGIFToTextures(gifData: $0)
			}
	}

	/**
	Request cancellation of the current generation.

	Monitor `eventStream` for `.cancelled` events.
	*/
	func cancelFullPreviewGeneration() {
		generationTask?.cancel()

		guard state.isGenerating else {
			return
		}

		updatePreview(newPreviewState: .cancelled(requestID: newID()))
	}

	private func updatePreview(newPreviewState: FullPreviewGenerationEvent) {
		guard newPreviewState.requestID >= state.requestID else {
			return
		}

		state = newPreviewState
		stateStreamContinuation.yield(newPreviewState)
	}
}

extension Int {
	/**
	For debugging `createPreviewStream`.
	*/
	func p(_ message: String) {
		#if DEBUG
//		print("\n\n\(self): \(message)\n\n")
		#endif
	}
}
