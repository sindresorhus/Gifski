import SwiftUI

// TODO: Rewrite the whole estimation thing.

@MainActor
@Observable
final class EstimatedFileSizeModel {
	var estimatedFileSize: String?
	var estimatedFileSizeNaive: String?
	var error: Error?

	// TODO: This is outside the scope of "file estimate", but it was easier to add this here than doing a separate SwiftUI view. This should be refactored out into a separate view when all of Gifski is SwiftUI.
	var duration = Duration.zero

	var getConversionSettings: (() -> GIFGenerator.Conversion)?
	private var gifski: GIFGenerator?

	private func getEstimatedFileSizeNaive() async -> String {
		await Int(getNaiveEstimate()).formatted(.byteCount(style: .file))
	}

	private func _estimateFileSize() {
		self.gifski = nil
		let gifski = GIFGenerator()
		self.gifski = gifski
		error = nil
		estimatedFileSize = nil

		Task {
			// TODO: Improve.
			duration = (try? await getConversionSettings?().gifDuration) ?? .zero
		}

		Task {
			estimatedFileSizeNaive = await getEstimatedFileSizeNaive()

			guard let settings = getConversionSettings?() else {
				return
			}

			do {
				let data = try await gifski.run(settings, isEstimation: true) { _ in }

				// We add 10% extra because it's better to estimate slightly too much than too little.
				let fileSize = await (Double(data.count) * gifski.sizeMultiplierForEstimation) * 1.1

				estimatedFileSize = Int(fileSize).formatted(.byteCount(style: .file))
			} catch {
				guard !(error is CancellationError) else {
					return
				}

				if case .notEnoughFrames = error as? GIFGenerator.Error {
					estimatedFileSize = await getEstimatedFileSizeNaive()
				} else {
					self.error = error
				}
			}
		}
	}

	func updateEstimate() {
		Debouncer.debounce(delay: .seconds(0.5), action: _estimateFileSize)
	}

	private func getNaiveEstimate() async -> Double {
		guard
			let conversionSettings = getConversionSettings?(),
			let duration = try? await conversionSettings.gifDuration
		else {
			return 0
		}

		let frameCount = duration.toTimeInterval * Defaults[.outputFPS].toDouble // TODO: Needs to be live.
		let dimensions = conversionSettings.dimensions ?? (0, 0) // TODO: Get asset dimensions.
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
