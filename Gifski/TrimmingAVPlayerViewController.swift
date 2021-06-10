import Combine
import AVKit

/// VC containing AVPlayerView and also extending possibilities for trimming (view) customization.
final class TrimmingAVPlayerViewController: NSViewController {
	private(set) var timeRange: ClosedRange<Double>?
	private let playerItem: AVPlayerItem
	private let player: LoopingPlayer
	private let controlsStyle: AVPlayerViewControlsStyle
	private let timeRangeDidChange: ((ClosedRange<Double>) -> Void)?

	var playerView: TrimmingAVPlayerView { view as! TrimmingAVPlayerView }

	/// The minimum duration the trimmer can be set to.
	var minimumTrimDuration = 0.1 {
		didSet {
			playerView.minimumTrimDuration = minimumTrimDuration
		}
	}

	var loopPlayback: Bool {
		get { player.loopPlayback }
		set {
			player.loopPlayback = newValue
		}
	}

	var bouncePlayback: Bool {
		get { player.bouncePlayback }
		set {
			player.bouncePlayback = newValue
		}
	}

	init(
		playerItem: AVPlayerItem,
		controlsStyle: AVPlayerViewControlsStyle = .inline,
		timeRangeDidChange: ((ClosedRange<Double>) -> Void)? = nil
	) {
		self.playerItem = playerItem
		self.player = LoopingPlayer(playerItem: playerItem)
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
		playerView.controlsStyle = controlsStyle
		playerView.setupTrimmingObserver()
		playerView.player = player
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
	private var timeRangeCancellable: AnyCancellable?
	private var trimmingCancellable: AnyCancellable?

	/// The minimum duration the trimmer can be set to.
	var minimumTrimDuration = 0.1

	// TODO: This should be a Combine publisher.
	fileprivate func observeTrimmedTimeRange(_ updateClosure: @escaping (ClosedRange<Double>) -> Void) {
		var skipNextUpdate = false

		timeRangeCancellable = player?.currentItem?.publisher(for: \.duration, options: .new)
			.sink { [weak self] _ in
				guard
					let self = self,
					let item = self.player?.currentItem,
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
		trimmingCancellable = publisher(for: \.canBeginTrimming, options: .new)
			.sink { [weak self] canBeginTrimming in
				guard
					let self = self,
					canBeginTrimming
				else {
					return
				}

				self.beginTrimming(completionHandler: nil)
				self.trimmingCancellable = nil
			}
	}

	fileprivate func hideTrimButtons() {
		// This method is a collection of hacks, so it might be acting funky on different OS versions.
		guard
			let avTrimView = firstSubview(deep: true, where: { $0.simpleClassName == "AVTrimView" }),
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
			.forEach {
				$0.isHidden = true
			}
	}

	fileprivate func addCheckerboardView() {
		let overlayView = CheckerboardView(frame: frame, clearRect: videoBounds)
		contentOverlayView?.addSubview(overlayView)
	}

	/// Prevent user from dismissing trimming view
	override func cancelOperation(_ sender: Any?) {}
}
