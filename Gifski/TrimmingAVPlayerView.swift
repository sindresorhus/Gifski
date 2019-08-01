import AVKit

/// AVPlayerView subclass that allows for more customization when working with Trimming.
final class TrimmingAVPlayerView: AVPlayerView {
	private var timeRangeObserver: NSKeyValueObservation?
	private var trimmingObserver: NSKeyValueObservation?

	override func awakeFromNib() {
		super.awakeFromNib()

		setup()
	}

	private func setup() {
		trimmingObserver = observe(\.canBeginTrimming, options: .new) { [weak self] _, change in
			if let canBeginTrimming = change.newValue, canBeginTrimming {
				self?.beginTrimming(completionHandler: nil)
				self?.trimmingObserver?.invalidate()
			}
		}
	}

	func observeTrimmedTimeRange(_ updateClosure: @escaping (ClosedRange<Double>) -> Void) {
		// Observing duration seems buggy on Mojave -> once we change min target to Catalina,
		// observe \.duration instead of \.forwardPlaybackEndTime
		timeRangeObserver = player?.currentItem?.observe(\.forwardPlaybackEndTime, options: .new) { item, _ in
			let startTime = item.reversePlaybackEndTime.seconds
			let endTime = item.forwardPlaybackEndTime.seconds
			if !startTime.isNaN && !endTime.isNaN {
				updateClosure(startTime...endTime)
			}
		}
	}

	func hideTrimButtons() {
		// This method is a collection of hacks, so might be acting funky on different OS versions
		guard
			let avTrimView = firstSubview(where: { $0.simpleClassName == "AVTrimView" }, deep: true),
			let superview = avTrimView.superview
		else {
			return
		}

		// First find the constraint for trimView that pins to the left edge of the button
		// Then replace the left edge of a button with the right edge - this will stretch the trim view
		if let constraint = superview.constraints.first(where: {
			($0.firstItem as? NSView) == avTrimView && $0.firstAttribute == .right
		}) {
			superview.removeConstraint(constraint)
			constraint.changing(secondAttribute: .right).isActive = true
		}

		if let constraint = superview.constraints.first(where: {
			($0.secondItem as? NSView) == avTrimView && $0.secondAttribute == .right
		}) {
			superview.removeConstraint(constraint)
			constraint.changing(firstAttribute: .right).isActive = true
		}

		// Now find buttons that are not images (images are playing controls) and hide them
		superview.subviews
			.first { $0 != avTrimView }?
			.subviews
			.filter { ($0 as? NSButton)?.image == nil }
			.forEach { $0.isHidden = true }
	}
}
