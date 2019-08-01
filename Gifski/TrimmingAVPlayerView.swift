import AVKit

final class TrimmingAVPlayerView: AVPlayerView {
	private var timeRangeObserver: NSKeyValueObservation?

	func observeTrimmedTimeRange(_ updateClosure: @escaping (ClosedRange<Double>) -> Void) {
		timeRangeObserver = player?.currentItem?.observe(\.duration, options: [.new]) { item, _ in
			let startTime = item.reversePlaybackEndTime.seconds
			let endTime = item.forwardPlaybackEndTime.seconds
			if !startTime.isNaN && !endTime.isNaN {
				updateClosure(startTime...endTime)
			}
		}
	}

	func hideTrimButtons() {
		// This method is a collection of hacks, so might be acting funky on different OS versions
		let avTrimView = firstSubview(where: { $0.description.contains("AVTrimView") }, deep: true)

		if let avTrimView = avTrimView {
			let superview = avTrimView.superview

			// First find the constraint for trimView that pins to the left edge of the button
			// Then replace the left edge of a button with the right edge - this will stretch the trim view
			if let constraint = superview?.constraints.first(where: {
				($0.firstItem as? NSView) == avTrimView && $0.firstAttribute == .right
			}) {
				superview?.removeConstraint(constraint)
				constraint.changing(secondAttribute: .right).isActive = true
			}

			if let constraint = superview?.constraints.first(where: {
				($0.secondItem as? NSView) == avTrimView && $0.secondAttribute == .right
			}) {
				superview?.removeConstraint(constraint)
				constraint.changing(firstAttribute: .right).isActive = true
			}

			// Now find buttons that are not images (images are playing controls) and hide them
			superview?.subviews
				.first { $0 != avTrimView }?
				.subviews
				.filter { ($0 as? NSButton)?.image == nil }
				.forEach { $0.isHidden = true }
		}
	}
}
