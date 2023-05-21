import SwiftUI
import FirebaseCrashlytics

final class EstimatedFileSizeModel: ObservableObject {
	@Published var estimatedFileSize: String?
	@Published var error: Error?

	// This is outside the scope of "file estimate", but it was easier to add this here than doing a separate SwiftUI view. This should be refactored out into a separate view when all of Gifski is SwiftUI.
	@Published var duration = Duration.zero

	var estimatedFileSizeNaive: String {
		Int(getNaiveEstimate()).formatted(.byteCount(style: .file))
	}

	private let getConversionSettings: () -> GIFGenerator.Conversion
	private let getNaiveEstimate: () -> Double
	private let getIsConverting: () -> Bool
	private var gifski: GIFGenerator?

	init(
		getConversionSettings: @escaping () -> GIFGenerator.Conversion,
		getNaiveEstimate: @escaping () -> Double,
		getIsConverting: @escaping () -> Bool
	) {
		self.getConversionSettings = getConversionSettings
		self.getNaiveEstimate = getNaiveEstimate
		self.getIsConverting = getIsConverting
	}

	private func _estimateFileSize() {
		cancel()

		guard !getIsConverting() else {
			return
		}

		let gifski = GIFGenerator()
		self.gifski = gifski

		estimatedFileSize = nil
		error = nil

		gifski.run(getConversionSettings(), isEstimation: true) { [weak self] result in
			guard let self else {
				return
			}

			switch result {
			case .success(let data):
				// We add 10% extra because it's better to estimate slightly too much than too little.
				let fileSize = (Double(data.count) * gifski.sizeMultiplierForEstimation) * 1.1

				estimatedFileSize = Int(fileSize).formatted(.byteCount(style: .file))
			case .failure(let error):
				switch error {
				case .cancelled:
					break
				case .notEnoughFrames:
					estimatedFileSize = estimatedFileSizeNaive
				default:
					Crashlytics.recordNonFatalError(error: error)
					self.error = error
				}
			}
		}
	}

	func cancel() {
		// It's important to call the cancel method as nil'ing out gifski doesn't properly cancel it.
		gifski?.cancel()
		gifski = nil
	}

	func updateEstimate() {
		Debouncer.debounce(delay: .seconds(0.5), action: _estimateFileSize)
		duration = getConversionSettings().gifDuration
	}
}

struct EstimatedFileSizeView: View {
	@StateObject private var model: EstimatedFileSizeModel

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
					Text(model.estimatedFileSize ?? model.estimatedFileSizeNaive)
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
					// This causes SwiftUI to crash internally on macOS 12.0 when changing the trim size many times so the estimation indicator keeps changing.
//					.animation(.easeInOut, value: model.estimatedFileSize)
			}
		}
			// It's important to set a width here as otherwise it can cause internal SwiftUI crashes on macOS 11 and 12.
			.frame(width: 500, height: 22, alignment: .leading)
			.overlay {
				if model.error == nil {
					HStack {
						let formattedDuration = model.duration.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2, fractionalSecondsLength: 2)))
						Text(formattedDuration)
							.monospacedDigit()
							.padding(.horizontal, 6)
							.padding(.vertical, 3)
							.background(Color.primary.opacity(0.04))
							.clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
					}
						.padding(.leading, 220)
				}
			}
			.task {
				if model.estimatedFileSize == nil {
					model.updateEstimate()
				}
			}
	}
}
