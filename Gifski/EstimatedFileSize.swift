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

	// This is outside the scope of "file estimate", but it was easier to add this here than doing a separate SwiftUI view. This should be refactored out into a separate view when all of Gifski is SwiftUI.
	@Published var duration: TimeInterval = 0

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
			guard let self else {
				return
			}

			switch result {
			case .success(let data):
				// We add 10% extra because it's better to estimate slightly too much than too little.
				let fileSize = (Double(data.count) * gifski.sizeMultiplierForEstimation) * 1.1

				// TODO: Use the new formatter API when targeting macOS 12.
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
						// TODO: Use `View#monospacedDigit()` when targeting macOS 12.
						.font(.system(size: 13).monospacedDigit())
						.foregroundColor(model.estimatedFileSize == nil ? .secondary : .primary)
				}
					.foregroundColor(.secondary)
				HStack {
					if model.estimatedFileSize == nil {
						ProgressView()
							.controlSize(.mini)
							.padding(.leading, -4)
							.help("Calculating file size estimate")
					}
				}
					// This causes SwiftUI to crash internally on macOS 12.0 when changing the trim size many times so the estimation indicator keeps changing.
//					.animation(.easeInOut, value: model.estimatedFileSize)
			}
		}
			// It's important to set a width here as otherwise it can cause internal SwiftUI crashes on macOS 11 and 12.
			.frame(width: 500, height: 22, alignment: .leading)
			.overlay2 {
				if model.error == nil {
					HStack {
						Text(DateComponentsFormatter.localizedStringPositionalWithFractionalSeconds(model.duration))
							// TODO: Use `View#monospacedDigit()` when targeting macOS 12.
							.font(.system(size: 13).monospacedDigit())
							.padding(.horizontal, 6)
							.padding(.vertical, 3)
							.background(Color.primary.opacity(0.04))
							.clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
					}
						.padding(.leading, 220)
				}
			}
			.onAppear {
				if model.estimatedFileSize == nil {
					model.updateEstimate()
				}
			}
	}
}
