import SwiftUI
import AVFoundation
import DockProgress

struct ConversionScreen: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(AppState.self) private var appState
	@State private var progress = 0.0
	@State private var timeRemaining: String?
	@State private var startTime: Date?

	let conversion: GIFGenerator.Conversion

	var body: some View {
		VStack {
			ProgressView(value: progress)
				.progressViewStyle(
					.ssCircular(
						fill: LinearGradient(
							gradient: .init(
								colors: [
									.purple,
									.pink,
									.orange
								]
							),
							startPoint: .top,
							endPoint: .bottom
						),
						lineWidth: 30,
						text: "Converting"
					)
				)
				.frame(width: 300, height: 300)
				.overlay {
					Group {
						if let timeRemaining {
							Text(timeRemaining)
								.font(.subheadline)
								.monospacedDigit()
								.offset(y: 24)
						}
					}
					.animation(.default, value: timeRemaining == nil)
				}
				.offset(y: -16) // Makes it centered (needed because of toolbar).
		}
		.fillFrame()
		.onKeyboardShortcut(.escape, modifiers: []) {
			dismiss()
		}
		.navigationTitle("")
		.task(priority: .utility) {
			do {
				try await convert()
			} catch {
				if !(error is CancellationError) {
					print("Conversion error:", error)
					appState.error = error
				}

				// So it doesn't get triggered when we press Escape to cancel.
				if !Task.isCancelled {
					dismiss()
				}
			}
		}
		.activity(options: .userInitiated, reason: "Converting")
	}

	func convert() async throws {
		startTime = .now

		defer {
			timeRemaining = nil
			DockProgress.resetProgress()
		}

		let data = try await GIFGenerator.run(conversion) { progress in
			self.progress = progress
			updateEstimatedTimeRemaining(for: progress)

			// This should not be needed. It silences a thread sanitizer warning.
			Task { @MainActor in
				DockProgress.progress = progress
			}
		}

		try Task.checkCancellation()

		let filename = conversion.sourceURL.filenameWithoutExtension
		let url = try data.writeToUniqueTemporaryFile(filename: filename, contentType: .gif)
		try? url.setAppAsItemCreator()

		try await Task.sleep(for: .seconds(1)) // Let the progress circle finish.

		// TODO: Support task cancellation.
		// TODO: Make sure it deinits too.

//		appState.navigationPath.removeLast()
//		appState.navigationPath.append(.completed(data))

		// This works around some race issue where it would sometimes end up with edit screen after conversion.
		var path = appState.navigationPath
		path.removeLast()
		path.append(.completed(data, url))
		appState.navigationPath = path
	}

	private func updateEstimatedTimeRemaining(for progress: Double) {
		guard
			progress > 0,
			let startTime
		else {
			timeRemaining = nil
			return
		}

		/**
		The delay before revealing the estimated time remaining, allowing the estimation to stabilize.
		*/
		let bufferDuration = Duration.seconds(3)

		/**
		Don't show the estimate at all if the total time estimate (after it stabilizes) is less than this amount.
		*/
		let skipThreshold = Duration.seconds(10)

		/**
		Begin fade out when remaining time reaches this amount.
		*/
		let fadeOutThreshold = Duration.seconds(1)

		let elapsed = Duration.seconds(Date.now.timeIntervalSince(startTime))
		let remaining = (elapsed / progress) * (1 - progress)
		let total = elapsed + remaining

		guard
			elapsed > bufferDuration,
			remaining > fadeOutThreshold,
			total > skipThreshold
		else {
			timeRemaining = nil
			return
		}

		let formatter = DateComponentsFormatter()
		formatter.unitsStyle = .full
		formatter.includesApproximationPhrase = true
		formatter.includesTimeRemainingPhrase = true
		formatter.allowedUnits = remaining < .seconds(60) ? .second : [.hour, .minute]
		timeRemaining = formatter.string(from: remaining.toTimeInterval)
	}
}
