import AVKit

/// VC containing AVPlayerView and also extending possibilities for trimming (view) customization.
final class TrimmingAVPlayerViewController: NSViewController {
	private(set) var timeRange: ClosedRange<Double>?
	private let playerItem: AVPlayerItem
	private let controlsStyle: AVPlayerViewControlsStyle
	private let timeRangeDidChange: ((ClosedRange<Double>) -> Void)?

	var playerView: TrimmingAVPlayerView { view as! TrimmingAVPlayerView }

	/// The minimum duration the trimmer can be set to.
	var minimumTrimDuration = 0.1 {
		didSet {
			playerView.minimumTrimDuration = minimumTrimDuration
		}
	}

	init(
		playerItem: AVPlayerItem,
		controlsStyle: AVPlayerViewControlsStyle = .inline,
		timeRangeDidChange: ((ClosedRange<Double>) -> Void)? = nil
	) {
		self.playerItem = playerItem
		self.controlsStyle = controlsStyle
		self.timeRangeDidChange = timeRangeDidChange
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		let playerView = TrimmingAVPlayerView()
		playerView.player = AVPlayer(playerItem: playerItem)
		playerView.controlsStyle = controlsStyle
		playerView.setupTrimmingObserver()

		view = playerView
	}

	override func viewDidAppear() {
		super.viewDidAppear()

		playerView.addCheckerboardView()
		playerView.hideTrimButtons()
		playerView.observeTrimmedTimeRange { [weak self] timeRange in
			self?.timeRange = timeRange
			self?.timeRangeDidChange?(timeRange)
		}
	}
}

final class TrimmingAVPlayerView: AVPlayerView {
	private var timeRangeObserver: NSKeyValueObservation?
	private var trimmingObserver: NSKeyValueObservation?

	/// The minimum duration the trimmer can be set to.
	var minimumTrimDuration = 0.1

	fileprivate func observeTrimmedTimeRange(_ updateClosure: @escaping (ClosedRange<Double>) -> Void) {
		var skipNextUpdate = false

		// Observing `.duration` seems buggy on macOS 10.14.
		// Once we change minimum target to 10.15,
		// observe `\.duration` instead of `\.forwardPlaybackEndTime`.
		timeRangeObserver = player?.currentItem?.observe(\.forwardPlaybackEndTime, options: .new) { item, _ in
			guard
				let fullRange = item.durationRange,
				let playbackRange = item.playbackRange
			else {
				return
			}

			/// Prevent infinite recursion.
			guard !skipNextUpdate else {
				skipNextUpdate = false
				updateClosure(playbackRange.minimumRangeLength(of: self.minimumTrimDuration, in: fullRange))
				return
			}

			guard playbackRange.length > self.minimumTrimDuration else {
				skipNextUpdate = true
				item.playbackRange = playbackRange.minimumRangeLength(of: self.minimumTrimDuration, in: fullRange)
				return
			}

			updateClosure(playbackRange)
		}
	}

	fileprivate func setupTrimmingObserver() {
		trimmingObserver = observe(\.canBeginTrimming, options: .new) { [weak self] _, change in
			if let canBeginTrimming = change.newValue, canBeginTrimming {
				self?.beginTrimming(completionHandler: nil)
				self?.trimmingObserver?.invalidate()
			}
		}
	}

	fileprivate func hideTrimButtons() {
		// This method is a collection of hacks, so it might be acting funky on different OS versions.
		guard
			let avTrimView = firstSubview(where: { $0.simpleClassName == "AVTrimView" }, deep: true),
			let superview = avTrimView.superview
		else {
			return
		}

		// First find the constraints for `avTrimView` that pins to the left edge of the button.
		// Then replace the left edge of a button with the right edge - this will stretch the trim view.
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

		// Now find buttons that are not images (images are playing controls) and hide them.
		superview.subviews
			.first { $0 != avTrimView }?
			.subviews
			.filter { ($0 as? NSButton)?.image == nil }
			.forEach { $0.isHidden = true }
	}

	fileprivate func addCheckerboardView() {
		let overlayView = CheckerboardView(frame: frame, clearRect: videoBounds)
		contentOverlayView?.addSubview(overlayView)
	}

	/// Prevent user from dismissing trimming view
	override func cancelOperation(_ sender: Any?) {}
}
