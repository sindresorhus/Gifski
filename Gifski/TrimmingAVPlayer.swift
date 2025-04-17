import AVKit
import SwiftUI

struct TrimmingAVPlayer: NSViewControllerRepresentable {
	typealias NSViewControllerType = TrimmingAVPlayerViewController

	let asset: AVAsset
	var controlsStyle = AVPlayerViewControlsStyle.inline
	var loopPlayback = false
	var bouncePlayback = false
	var speed = 1.0


	var onScrubToNewTime: ((AVPlayer, Double) -> Void)?
	var rateDidChange: ((AVPlayer, Float) -> Void)?
	var enablePlayButton = true
	var pauseOnLoop = true
	var viewUnderTrim: NSView?

	var timeRangeDidChange: ((ClosedRange<Double>) -> Void)?

	func makeNSViewController(context: Context) -> NSViewControllerType {
		.init(
			playerItem: .init(asset: asset),
			controlsStyle: controlsStyle,
			onScrubToNewTime: onScrubToNewTime,
			rateDidChange: rateDidChange,
			timeRangeDidChange: timeRangeDidChange
		)
	}

	func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context) {
		if asset != nsViewController.currentItem.asset {
			nsViewController.currentItem = .init(asset: asset)
		}

		nsViewController.loopPlayback = loopPlayback
		nsViewController.bouncePlayback = bouncePlayback
		nsViewController.player.defaultRate = Float(speed)

		nsViewController.enablePlayButton = enablePlayButton
		nsViewController.viewUnderTrim = viewUnderTrim
		nsViewController.player.pauseOnLoop = pauseOnLoop


		if nsViewController.player.rate != 0 {
			nsViewController.player.rate = nsViewController.player.rate > 0 ? Float(speed) : -Float(speed)
		}
	}
}



// TODO: Move more of the logic here over to the SwiftUI view.
/**
A view controller containing AVPlayerView and also extending possibilities for trimming (view) customization.
*/
final class TrimmingAVPlayerViewController: NSViewController {
	private(set) var timeRange: ClosedRange<Double>?
	private let playerItem: AVPlayerItem
	fileprivate let player: LoopingPlayer
	private let controlsStyle: AVPlayerViewControlsStyle
	private let timeRangeDidChange: ((ClosedRange<Double>) -> Void)?
	private var cancellables = Set<AnyCancellable>()
	private let onScrubToNewTime: ((AVPlayer, Double) -> Void)?
	private let rateDidChange: ((AVPlayer, Float) -> Void)?


	fileprivate var enablePlayButton = true {
		didSet {
			guard oldValue != enablePlayButton else {
				return
			}
			playerView.enableOrDisablePlayButton(enable: enablePlayButton)
		}
	}


	fileprivate var viewUnderTrim: NSView? {
		didSet {
			guard oldValue != viewUnderTrim else {
				return
			}
			oldValue?.removeFromSuperview()
			guard let viewUnderTrim else {
				return
			}
			playerView.contentOverlayView?.addSubview(viewUnderTrim)
			viewUnderTrim.constrainEdgesToSuperview()
		}
	}


	var playerView: TrimmingAVPlayerView { view as! TrimmingAVPlayerView }

	/**
	The minimum duration the trimmer can be set to.
	*/
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

	/**
	Get or set the current player item.

	When setting an item, it preserves the current playback rate (which means pause state too), playback position, and trim range.
	*/
	var currentItem: AVPlayerItem {
		get { player.currentItem! }
		set {
			let rate = player.rate
			let playbackPercentage = player.currentItem?.playbackProgress ?? 0
			let playbackRangePercentage = player.currentItem?.playbackRangePercentage

			player.replaceCurrentItem(with: newValue)

			DispatchQueue.main.async { [self] in
				player.rate = rate
				player.currentItem?.seek(toPercentage: playbackPercentage)
				player.currentItem?.playbackRangePercentage = playbackRangePercentage
			}
		}
	}

	init(
		playerItem: AVPlayerItem,
		controlsStyle: AVPlayerViewControlsStyle = .inline,
		onScrubToNewTime: ((AVPlayer, Double) -> Void)? = nil,
		rateDidChange: ((AVPlayer, Float) -> Void)? = nil,
		timeRangeDidChange: ((ClosedRange<Double>) -> Void)? = nil
	) {
		self.playerItem = playerItem
		self.player = LoopingPlayer(playerItem: playerItem)
		self.controlsStyle = controlsStyle
		self.timeRangeDidChange = timeRangeDidChange
		self.rateDidChange = rateDidChange
		self.onScrubToNewTime = onScrubToNewTime

		super.init(nibName: nil, bundle: nil)
	}

	deinit {
		print("TrimmingAVPlayerViewController - DEINIT")
	}


	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func loadView() {
		let playerView = TrimmingAVPlayerView()
		playerView.allowsVideoFrameAnalysis = false
		playerView.controlsStyle = controlsStyle
		playerView.player = player
		view = playerView
	}



	override func viewDidLoad() {
		super.viewDidLoad()

		// Support replacing the item.
		player.publisher(for: \.currentItem)
			.compactMap(\.self)
			.flatMap { currentItem in
				// TODO: Make a `AVPlayerItem#waitForReady` async property when using Swift 6.
				currentItem.publisher(for: \.status)
					.first { $0 == .readyToPlay }
					.map { _ in currentItem }
			}
			.receive(on: DispatchQueue.main)
			.sink { [weak self] in
				guard let self else {
					return
				}

				playerView.setupTrimmingObserver()

				if let durationRange = $0.durationRange {
					timeRangeDidChange?(durationRange)
				}

				// This is here as it needs to be refreshed when the current item changes.
				playerView.observeTrimmedTimeRange { [weak self] timeRange in
					self?.timeRange = timeRange
					self?.timeRangeDidChange?(timeRange)
				}
			}
			.store(in: &cancellables)

		player
			.publisher(for: \.rate)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] newRate in
				guard let self else {
					return
				}
				rateDidChange?(player, newRate)
			}
			.store(in: &cancellables)

		Task {
			for await time in self.player.scrubTimeStream() {
				self.onScrubToNewTime?(self.player, time.toTimeInterval)
			}
		}
	}
}



final class TrimmingAVPlayerView: AVPlayerView {
	private var timeRangeCancellable: AnyCancellable?
	private var trimmingCancellable: AnyCancellable?

	/**
	The minimum duration the trimmer can be set to.
	*/
	var minimumTrimDuration = 0.1

	deinit {
		print("TrimmingAVPlayerView - DEINIT")
	}

	// TODO: This should be an AsyncSequence.
	fileprivate func observeTrimmedTimeRange(_ updateClosure: @escaping (ClosedRange<Double>) -> Void) {
		var skipNextUpdate = false

		timeRangeCancellable = player?.currentItem?.publisher(for: \.duration, options: .new)
			.sink { [weak self] _ in
				guard
					let self,
					let item = player?.currentItem,
					let fullRange = item.durationRange,
					let playbackRange = item.playbackRange
				else {
					return
				}

				// Prevent infinite recursion.
				guard !skipNextUpdate else {
					skipNextUpdate = false
					updateClosure(playbackRange.minimumRangeLength(of: minimumTrimDuration, in: fullRange))
					return
				}

				guard playbackRange.length > minimumTrimDuration else {
					skipNextUpdate = true
					item.playbackRange = playbackRange.minimumRangeLength(of: minimumTrimDuration, in: fullRange)
					return
				}

				updateClosure(playbackRange)
			}
	}

	fileprivate func setupTrimmingObserver() {
		trimmingCancellable = Task {
			do {
				try await activateTrimming()
				addCheckerboardView()
				hideTrimButtons()
				window?.makeFirstResponder(self)
			} catch {}
		}
		.toCancellable
	}

	var playPauseButtonTarget: AnyObject?

	fileprivate func setPlayButtonEnabled(_ enabled: Bool) {
		guard
			let avTrimView = firstSubview(deep: true, where: { $0.simpleClassName == "AVTrimView" }),
			let superview = avTrimView.superview
		else {
			return
		}
		guard let playPauseButton = (superview.subviews
			.first { $0 != avTrimView }?
			.subviews
			.first {
				guard let button = ($0 as? NSButton),
				button.action?.description == "playPauseButtonPressed:" else {
					return false
				}
				return true
			} as? NSButton) else {
				return
			}
		if playPauseButton.target !== self {
			playPauseButtonTarget = playPauseButton.target
			playPauseButton.target = self
		}

		playPauseButton.isEnabled = enable
	}

	@objc func playPauseButtonPressed(_ sender: Any) {
		if let loopingPlayer = player as? LoopingPlayer,
		/**
		 only prevent time change notifications on play button press,
		 not pause button press
		 */
		loopingPlayer.rate == 0 {
			loopingPlayer.timeChangeDueToLoopBounceOrPlayButtonPress = true
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				loopingPlayer.timeChangeDueToLoopBounceOrPlayButtonPress = false
			}
		}
		NSApp.sendAction(#selector(self.playPauseButtonPressed(_:)), to: playPauseButtonTarget, from: sender)
	}

	fileprivate func hideTrimButtons(enablePlayButton: Bool = true) {
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
		let overlayView = NSHostingView(rootView: CheckerboardView(clearRect: videoBounds))
		contentOverlayView?.addSubview(overlayView)
		overlayView.constrainEdgesToSuperview()
	}

	/**
	Prevent user from dismissing trimming view.
	*/
	override func cancelOperation(_ sender: Any?) {}
}
