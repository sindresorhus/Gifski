import SwiftUI
import FirebaseCrashlytics

final class EstimatedFileSizeModel: ObservableObject {
	static let formatter: ByteCountFormatter = {
		let formatter = ByteCountFormatter()
		formatter.zeroPadsFractionDigits = true
		return formatter
	}()

	@Published var estimatedFileSize: String?
	@Published var error: Error?

	var estimatedFileSizeNaive: String {
		Self.formatter.string(fromByteCount: Int64(getNaiveEstimate()))
	}

	private let getConversionSettings: () -> Gifski.Conversion
	private let getNaiveEstimate: () -> Double
	private let getIsConverting: () -> Bool
	private var gifski: Gifski?

	init(
		getConversionSettings: @escaping () -> Gifski.Conversion,
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

		let gifski = Gifski()
		self.gifski = gifski

		estimatedFileSize = nil
		error = nil

		gifski.run(getConversionSettings(), isEstimation: true) { [weak self] result in
			guard let self = self else {
				return
			}

			switch result {
			case .success(let data):
				// We add 10% extra because it's better to estimate slightly too much than too little.
				let fileSize = (Double(data.count) * gifski.sizeMultiplierForEstimation) * 1.1

				self.estimatedFileSize = Self.formatter.string(fromByteCount: Int64(fileSize))
			case .failure(let error):
				switch error {
				case .cancelled:
					break
				case .notEnoughFrames:
					self.estimatedFileSize = self.estimatedFileSizeNaive
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
		Debouncer.debounce(delay: 0.5, action: _estimateFileSize)
	}
}

struct EstimatedFileSizeView: View {
	// TODO: Use `StateObject` when targeting macOS 11.
	@ObservedObject private var model: EstimatedFileSizeModel

	init(model: EstimatedFileSizeModel) {
		_model = .init(wrappedValue: model)
	}

	var body: some View {
		HStack {
			if let error = model.error {
				Text("Failed to get estimate: \(error.localizedDescription)")
					// TODO: Enable when targeting macOS 11.
//					.help(error.localizedDescription)
			} else {
				HStack(spacing: 0) {
					Text("Estimated size: ")
					Text(model.estimatedFileSize ?? model.estimatedFileSizeNaive)
						.font(.system(size: 13).monospacedDigit())
						.foregroundColor(model.estimatedFileSize == nil ? .secondary : .primary)
				}
					.foregroundColor(.secondary)
				HStack {
					if model.estimatedFileSize == nil {
						if #available(macOS 11, *) {
							ProgressView()
								.controlSize(.small)
								.scaleEffect(0.7)
								.padding(.leading, -4)
								.help("Calculating file size estimate")
						} else {
							Text("Calculating Estimate…")
								.foregroundColor(.secondary)
								.font(.smallSystem())
						}
					}
				}
					.animation(.easeInOut, value: model.estimatedFileSize)
			}
		}
			.frame(height: 24)
			.onAppear {
				if model.estimatedFileSize == nil {
					model.updateEstimate()
				}
			}
	}
}
