import SwiftUI

@MainActor
@Observable
final class EstimatedFileSizeModel {
	var estimatedFileSize: String?
	/**
	Calibrated naive estimate shown while the sampling estimate is running.
	*/
	var estimatedFileSizeNaive: String?
	var error: Error?

	// TODO: This is outside the scope of "file estimate", but it was easier to add this here than doing a separate SwiftUI view. This should be refactored out into a separate view when all of Gifski is SwiftUI.
	var duration = Duration.zero

	var getConversionSettings: (() -> GIFGenerator.Conversion)?
	private var gifski: GIFGenerator?
	private var estimationTask: Task<Void, Never>?
	private var durationTask: Task<Void, Never>?
	private var estimateRequestID = 0
	private var fileSizeEstimateCalibration = FileSizeEstimateCalibration()

	private func formattedCalibratedNaiveEstimate(fromNaiveBytes naiveBytes: Double) -> String {
		formattedFileSize(fileSizeEstimateCalibration.calibratedBytes(fromNaiveBytes: naiveBytes))
	}

	private func formattedFileSize(_ bytes: Double) -> String {
		Int(bytes).formatted(.byteCount(style: .file))
	}

	private func _estimateFileSize() {
		// Cancel any previous tasks to prevent stale results from overwriting newer ones.
		estimationTask?.cancel()
		durationTask?.cancel()
		estimateRequestID += 1
		let estimateRequestID = self.estimateRequestID

		self.gifski = nil
		let gifski = GIFGenerator()
		self.gifski = gifski
		error = nil
		estimatedFileSize = nil

		durationTask = Task {
			// TODO: Improve.
			let updatedDuration = (try? await getConversionSettings?().gifDuration) ?? .zero
			guard estimateRequestID == self.estimateRequestID else {
				return
			}

			duration = updatedDuration
		}

		estimationTask = Task {
			let naiveBytes = await getNaiveEstimateBytes()
			guard
				!Task.isCancelled,
				estimateRequestID == self.estimateRequestID
			else {
				return
			}

			estimatedFileSizeNaive = formattedCalibratedNaiveEstimate(fromNaiveBytes: naiveBytes)

			guard let settings = getConversionSettings?() else {
				return
			}

			do {
				let data = try await gifski.run(settings, isEstimation: true) { _ in }

				try Task.checkCancellation()

				// We add 10% extra because it's better to estimate slightly too much than too little.
				let fileSize = await (Double(data.count) * gifski.sizeMultiplierForEstimation) * 1.1

				try Task.checkCancellation()
				guard estimateRequestID == self.estimateRequestID else {
					return
				}

				fileSizeEstimateCalibration.update(naiveBytes: naiveBytes, betterBytes: fileSize)
				estimatedFileSize = formattedFileSize(fileSize)
			} catch {
				guard
					!Task.isCancelled,
					!(error is CancellationError),
					estimateRequestID == self.estimateRequestID
				else {
					return
				}

				if case .notEnoughFrames = error as? GIFGenerator.Error {
					estimatedFileSize = formattedCalibratedNaiveEstimate(fromNaiveBytes: naiveBytes)
				} else {
					self.error = error
				}
			}
		}
	}

	func updateEstimate() {
		Debouncer.debounce(delay: .seconds(0.5), action: _estimateFileSize)
	}

	private func getNaiveEstimateBytes() async -> Double {
		guard
			let conversionSettings = getConversionSettings?(),
			let duration = try? await conversionSettings.gifDuration
		else {
			return 0
		}

		let frameCount = duration.toTimeInterval * Defaults[.outputFPS].toDouble // TODO: Needs to be live.
		let dimensions = conversionSettings.croppedOutputDimensions ?? (0, 0) // TODO: Get asset dimensions.
		var fileSize = (dimensions.width.toDouble * dimensions.height.toDouble * frameCount) / 3
		fileSize = fileSize * (Defaults[.outputQuality] + 1.5) / 2.5

		return fileSize
	}
}

struct EstimatedFileSizeView: View {
	@State private var model: EstimatedFileSizeModel

	init(model: EstimatedFileSizeModel) {
		_model = .init(wrappedValue: model)
	}

	var body: some View {
		HStack {
			if let error = model.error {
				Text("Failed to get estimate: \(error.localizedDescription)")
					.help(error.localizedDescription)
			} else {
				HStack(spacing: 0) {
					Text("Estimated size: ")
					Text(model.estimatedFileSize ?? model.estimatedFileSizeNaive ?? "…")
						.monospacedDigit()
						.foregroundStyle(model.estimatedFileSize == nil ? .secondary : .primary)
				}
					.foregroundStyle(.secondary)
				if model.estimatedFileSize == nil {
					ProgressView()
						.controlSize(.mini)
						.padding(.leading, -4)
						.help("Calculating file size estimate")
				}
			}
		}
		.fillFrame(.horizontal, alignment: .leading)
		.overlay {
			if model.error == nil {
				HStack {
					let formattedDuration = model.duration.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2, fractionalSecondsLength: 2)))
					Text(formattedDuration)
						.monospacedDigit()
						.padding(.horizontal, 6)
						.padding(.vertical, 3)
						.background(Color.primary.opacity(0.04))
						.clipShape(.rect(cornerRadius: 4))
				}
			}
		}
		.task {
			if model.estimatedFileSize == nil {
				model.updateEstimate()
			}
		}
	}
}

/**
Improves naive file size estimates by applying a ratio learned from the latest sampling-based estimate.

The calibration is intentionally lightweight: a single ratio is remembered per session and applied to subsequent naive estimates while the sampling estimate is running.
*/
struct FileSizeEstimateCalibration {
	private(set) var ratio: Double?

	/**
	Updates the calibration ratio using the provided naive and sampling-based estimates.
	*/
	mutating func update(naiveBytes: Double, betterBytes: Double) {
		// Avoid poisoning the calibration with invalid or degenerate samples.
		guard
			naiveBytes > 0,
			betterBytes > 0,
			naiveBytes.isFinite,
			betterBytes.isFinite
		else {
			return
		}

		ratio = betterBytes / naiveBytes
	}

	/**
	Returns the calibrated estimate for a naive byte count.

	If no ratio is available yet, the naive value is returned unchanged.
	*/
	func calibratedBytes(fromNaiveBytes naiveBytes: Double) -> Double {
		guard let ratio else {
			return naiveBytes
		}

		return naiveBytes * ratio
	}
}
