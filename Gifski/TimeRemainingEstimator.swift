import Foundation

final class TimeRemainingEstimator {
	/// The delay before revealing the estimated time remaining, allowing the estimation to stabilize.
	let bufferDuration: TimeInterval = 3

	/// Don't show the estimate at all if the total time estimate (after it stabilizes) is less than this amount.
	let skipThreshold: TimeInterval = 10

	/// Begin fade out when remaining time reaches this amount.
	let fadeOutThreshold: TimeInterval = 1

	var progress: Progress? {
		didSet {
			progressObserver = progress?.observe(\.fractionCompleted) { sender, _ in
				self.percentComplete = sender.fractionCompleted
			}

			cancelObserver = progress?.observe(\.isCancelled) { sender, _ in
				if sender.isCancelled {
					self.state = .done
				}
			}
		}
	}

	init(label: Label) {
		self.label = label
	}

	func start() {
		state = .buffering
		startTime = Date()
	}

	// MARK: - Private

	private enum State {
		case buffering
		case running
		case done
	}

	private var state: State = .buffering {
		didSet {
			guard state != oldValue else {
				return
			}

			switch state {
			case .buffering:
				break
			case .running:
				fadeInLabel()
			case .done:
				fadeOutLabel()
			}
		}
	}

	private var nextState: State {
		switch state {
		case .buffering:
			if finishedBuffering {
				return shouldShowEstimation ? .running : .done
			} else {
				return .buffering
			}
		case .running:
			return secondsRemaining < fadeOutThreshold ? .done : .running
		case .done:
			return .done
		}
	}

	private var finishedBuffering: Bool { secondsElapsed > bufferDuration }
	private var shouldShowEstimation: Bool { secondsRemaining > skipThreshold }
	private var secondsElapsed: TimeInterval { Date().timeIntervalSince(startTime) }

	private var secondsRemaining: TimeInterval {
		(secondsElapsed / percentComplete) * (1 - percentComplete)
	}

	private let label: Label
	private var startTime = Date()
	private var progressObserver: NSKeyValueObservation?
	private var cancelObserver: NSKeyValueObservation?

	private lazy var elapsedTimeFormatter = with(DateComponentsFormatter()) {
		$0.unitsStyle = .full
		$0.includesApproximationPhrase = true
		$0.includesTimeRemainingPhrase = true
	}

	private var formattedTimeRemaining: String? {
		let seconds = secondsRemaining.clamped(to: 1...)
		elapsedTimeFormatter.allowedUnits = seconds < 60 ? .second : [.hour, .minute]
		return elapsedTimeFormatter.string(from: seconds)
	}

	private var percentComplete: Double = 0.001 {
		didSet {
			state = nextState
			updateLabel()
		}
	}

	private func fadeInLabel() {
		DispatchQueue.main.async {
			if self.label.isHidden {
				self.label.fadeIn()
			}
		}
	}

	private func fadeOutLabel() {
		DispatchQueue.main.async {
			if !self.label.isHidden {
				self.label.fadeOut()
			}
		}
	}

	private func updateLabel() {
		DispatchQueue.main.async {
			self.label.text = self.formattedTimeRemaining ?? ""
		}
	}
}
