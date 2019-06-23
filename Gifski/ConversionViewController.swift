import AppKit
import UserNotifications
import StoreKit

final class ConversionViewController: NSViewController {
	private lazy var circularProgress = with(CircularProgress(size: 160.0)) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.color = .themeColor
	}

	private lazy var timeRemainingLabel = with(Label()) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.isHidden = true
		$0.textColor = .secondaryLabelColor
		$0.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
	}

	private lazy var timeRemainingEstimator = TimeRemainingEstimator(label: timeRemainingLabel)

	private var conversion: Gifski.Conversion!
	private var progress: Progress?
	private var isRunning = false

	convenience init(conversion: Gifski.Conversion) {
		self.init()

		self.conversion = conversion
	}

	override func loadView() {
		let wrapper = NSView(frame: CGRect(origin: .zero, size: CGSize(width: 360, height: 240)))
		wrapper.addSubview(circularProgress)
		wrapper.addSubview(timeRemainingLabel)

		circularProgress.center(inView: wrapper)
		NSLayoutConstraint.activate([
			timeRemainingLabel.topAnchor.constraint(equalTo: circularProgress.bottomAnchor, constant: 8.0),
			timeRemainingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			timeRemainingLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: 8.0)
		])

		view = wrapper
	}

	private func startConversion(inputUrl: URL, outputUrl: URL) {
		guard !isRunning else {
			return
		}

		isRunning = true

		progress = Progress(totalUnitCount: 1)
		progress?.publish()

		circularProgress.progressInstance = progress
		DockProgress.progressInstance = progress
		timeRemainingEstimator.progress = progress
		timeRemainingEstimator.start()

		progress?.performAsCurrent(withPendingUnitCount: 1) {
			Gifski.run(conversion) { error in
				self.progress?.unpublish()
				self.isRunning = false

				if let error = error {
					self.progress?.cancel()

					switch error {
					case .cancelled:
						break
					default:
						self.presentError(error, modalFor: self.view.window)
					}

					return
				}

				defaults[.successfulConversionsCount] += 1
				if #available(macOS 10.14, *), defaults[.successfulConversionsCount] == 5 {
					SKStoreReviewController.requestReview()
				}

				if #available(macOS 10.14, *), !NSApp.isActive || self.view.window?.isVisible == false {
					let notification = UNMutableNotificationContent()
					notification.title = "Conversion Completed"
					notification.subtitle = outputUrl.filename
					let request = UNNotificationRequest(identifier: "conversionCompleted", content: notification, trigger: nil)
					UNUserNotificationCenter.current().add(request)
				}
			}
		}
	}

	private func cancelConversion() {
		progress?.cancel()
	}
}
