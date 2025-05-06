import AVKit
import SwiftUI

struct TrimmingAVPlayer: NSViewControllerRepresentable {
	typealias NSViewControllerType = TrimmingAVPlayerViewController

	let asset: AVAsset
	var controlsStyle = AVPlayerViewControlsStyle.inline
	var loopPlayback = false
	var bouncePlayback = false
	var speed = 1.0
	var overlay: AnyView?
	var isTrimmerDraggable = false
	var timeRangeDidChange: ((ClosedRange<Double>) -> Void)?

	func makeNSViewController(context: Context) -> NSViewControllerType {
		.init(
			playerItem: .init(asset: asset),
			controlsStyle: controlsStyle,
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
		nsViewController.player.rate = nsViewController.player.rate > 0 ? Float(speed) : -Float(speed)
		nsViewController.overlay = overlay
		nsViewController.isTrimmerDraggable = isTrimmerDraggable
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
	private var underTrimOverlayView: NSHostingView<AnyView>?

	fileprivate var overlay: AnyView? {
		didSet {
			if let underTrimOverlayView {
				underTrimOverlayView.removeFromSuperview()
			}
			guard let overlay else {
				underTrimOverlayView = nil
				return
			}

			let underTrimOverlayView = NSHostingView(rootView: overlay)
			playerView.contentOverlayView?.addSubview(underTrimOverlayView)
			underTrimOverlayView.translatesAutoresizingMaskIntoConstraints = false

			let videoBounds = playerView.videoBounds
			guard let contentOverlayView = playerView.contentOverlayView else {
				return
			}
			NSLayoutConstraint.activate([
				underTrimOverlayView.leadingAnchor.constraint(equalTo: contentOverlayView.leadingAnchor, constant: videoBounds.origin.x),
				underTrimOverlayView.topAnchor.constraint(equalTo: contentOverlayView.topAnchor, constant: videoBounds.origin.y),
				underTrimOverlayView.widthAnchor.constraint(equalToConstant: videoBounds.size.width),
				underTrimOverlayView.heightAnchor.constraint(equalToConstant: videoBounds.size.height)
			])
			self.underTrimOverlayView = underTrimOverlayView
		}
	}

	fileprivate var isTrimmerDraggable = false {
		didSet {
			trimmerDragViews?.isDraggable = isTrimmerDraggable
		}
	}

	var playerView: TrimmingAVPlayerView { view as! TrimmingAVPlayerView }

	/**
	 Can't use lazy here because at start this will be null before the player is initialized (there won't be an AVTrimView)
	 */
	private var _trimmerDragViews: TrimmerDragViews?

	private var trimmerDragViews: TrimmerDragViews? {
		if let _trimmerDragViews {
			return _trimmerDragViews
		}
		// Needed so that it will hide the trimmer when it is outside the view. This must be done now (as opposed to`viewDidLoad`) because layer is nil in `viewDidLoad`
		playerView.layer?.masksToBounds = true
		guard let avTrimView = (playerView.firstSubview(deep: true) { $0.simpleClassName == "AVTrimView" })?.superview,
			  let avTrimViewParent = avTrimView.superview?.superview else {
			return nil
		}
		_trimmerDragViews = TrimmerDragViews(avTrimView: avTrimView, avTrimViewParent: avTrimViewParent, isDraggable: false)
		return _trimmerDragViews
	}

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
		timeRangeDidChange: ((ClosedRange<Double>) -> Void)? = nil
	) {
		self.playerItem = playerItem
		self.player = LoopingPlayer(playerItem: playerItem)
		self.controlsStyle = controlsStyle
		self.timeRangeDidChange = timeRangeDidChange
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
		let overlayView = NSHostingView(rootView: CheckerboardView(clearRect: videoBounds))
		contentOverlayView?.addSubview(overlayView)
		overlayView.constrainEdgesToSuperview()
	}

	/**
	Prevent user from dismissing trimming view.
	*/
	override func cancelOperation(_ sender: Any?) {}
}

fileprivate class TrimmerDragViews {
	private var avTrimView: NSView
	/**
	 The view that holds the entire trimmer. The supermost view
	 */
	private var fullTrimmerView: CustomCursorView
	private var avTrimViewParent: NSView
	private var drawHandleView: NSHostingView<DragHandleView>

	var isDraggable = false {
		didSet {
			if isDraggable {
				showDrag()
			} else {
				hideDrag()
			}
		}
	}



	/**
	The initial offset of the trimmer from the bottom before we drag it anywhere
	 */
	static let dragBarHeight = 17.0
	static let newHeight = 87.0
	static let dragBarTopAnchor = 6.0
	/**
	 These offsets are computed before we swap the trimmer
	 */

	private let trimmerConstraints: TrimmerConstraints


	init(avTrimView: NSView, avTrimViewParent: NSView, isDraggable: Bool){
		self.avTrimView = avTrimView
		self.avTrimViewParent = avTrimViewParent
		self.fullTrimmerView = CustomCursorView()
		self.drawHandleView = NSHostingView(rootView: DragHandleView())

		trimmerConstraints = TrimmerConstraints(avTrimViewParent: avTrimViewParent)

		swapTrimmerSuperviews()
		self.isDraggable = isDraggable

		let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
		panGesture.delaysPrimaryMouseButtonEvents = false
		fullTrimmerView.addGestureRecognizer(panGesture)
	}
	/**
	 Remove the avTrimViewParent from its old location in the view hierarchy and swap with our fullTrimmerView.
	 */
	private func swapTrimmerSuperviews() {
		// The view that previously held the full trimmer view
		guard let oldSuperview = avTrimViewParent.superview else {
			return
		}

		avTrimViewParent.removeFromSuperview()

		fullTrimmerView.translatesAutoresizingMaskIntoConstraints = false
		fullTrimmerView.addSubview(avTrimViewParent)
		oldSuperview.addSubview(fullTrimmerView)

		avTrimViewParent.constrainEdgesToSuperview()

		trimmerConstraints.apply(toNewView: fullTrimmerView, avTrimViewParentSuperView: oldSuperview)
	}

	private func showDrag() {
		fullTrimmerView.addSubview(drawHandleView)
		drawHandleView.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			drawHandleView.leadingAnchor.constraint(equalTo: fullTrimmerView.leadingAnchor, constant: 0),
			drawHandleView.trailingAnchor.constraint(equalTo: fullTrimmerView.trailingAnchor, constant: 0),
			drawHandleView.topAnchor.constraint(equalTo: fullTrimmerView.topAnchor, constant: Self.dragBarTopAnchor),
			drawHandleView.heightAnchor.constraint(equalToConstant: Self.dragBarHeight)
		])

		fullTrimmerHeightConstraint?.constant = Self.newHeight
		trimmerWindowTopConstraint?.constant = Self.newHeight - trimmerConstraints.height
		trimmerBottomConstraint?.animate(to: trimmerConstraints.height) {
			self.avTrimView.isHidden = true
		}
	}

	private func hideDrag() {
		self.drawHandleView.removeFromSuperview()
		avTrimView.isHidden = false
		trimmerBottomConstraint?.animate(to: trimmerConstraints.bottomOffset)
		fullTrimmerHeightConstraint?.constant = trimmerConstraints.height
		trimmerWindowTopConstraint?.constant = 0
	}

	/**
	 Bound the view so that it can only go just a bit below the bottom and to the top. Then also bound the drag gesture so that your drags outside the view bounds won't affect the drag.
	 */
	@objc private func handleDrag(_ gesture: NSPanGestureRecognizer) {
		guard isDraggable,
			  let view = gesture.view,
			  let superview = view.superview,
			  let trimmerBottomConstraint else {
			return
		}
		let endLocation = gesture.location(in: superview).y
		let translation = gesture.translation(in: superview).y
		let startLocation = endLocation - translation
		defer {
			gesture.setTranslation(.zero, in: superview)
		}
		let bounds = superview.bounds.minY...superview.bounds.maxY
		guard bounds.contains(startLocation) else {
			return
		}
		let boundedTranslation = endLocation.clamped(to: bounds) - startLocation
		let newBottom = (trimmerBottomConstraint.constant - boundedTranslation).clamped(to: -superview.bounds.height + view.frame.height...trimmerConstraints.height)

		trimmerBottomConstraint.constant = newBottom
		avTrimView.isHidden = newBottom > trimmerConstraints.height - 2
	}

	private lazy var fullTrimmerHeightConstraint: NSLayoutConstraint? = {
		fullTrimmerView.constraints.first { $0.firstAttribute == .height && $0.firstItem as? NSView == fullTrimmerView }
	}()

	private lazy var trimmerBottomConstraint: NSLayoutConstraint? = {
		fullTrimmerView.getConstraintFromSuperview(attribute: .bottom)
	}()

	private lazy var trimmerWindowTopConstraint: NSLayoutConstraint? = {
		avTrimView.getConstraintFromSuperview(attribute: .top)
	}()
	/**
	 Grab the constraints on the trimmer while it is still constrained to its superview, so that when we move it to a new superview it will have no visual change
	 */
	private struct TrimmerConstraints {
		let bottomOffset: Double
		let leadingOffset: Double
		let trailingOffset: Double
		let height: Double

		init(avTrimViewParent: NSView){
			bottomOffset = -(avTrimViewParent.getConstraintConstantFromSuperView(attribute: .bottom) ?? 6.0)
			leadingOffset = avTrimViewParent.getConstraintConstantFromSuperView(attribute: .leading) ?? 6.0
			trailingOffset = -(avTrimViewParent.getConstraintConstantFromSuperView(attribute: .trailing) ?? 6.0)
			height = avTrimViewParent.getConstraintConstantFromSuperView(attribute: .height) ?? 64.0
		}
		/**
		 Apply the saved constraints to a new container view, placing it in the same position as avTrimViewParent used to be
		 */
		func apply(toNewView newView: NSView, avTrimViewParentSuperView oldSuperview: NSView) {
			NSLayoutConstraint.activate([
				newView.leadingAnchor.constraint(equalTo: oldSuperview.leadingAnchor, constant: leadingOffset),
				newView.bottomAnchor.constraint(equalTo: oldSuperview.bottomAnchor, constant: bottomOffset),
				newView.trailingAnchor.constraint(equalTo: oldSuperview.trailingAnchor, constant: trailingOffset),
				newView.heightAnchor.constraint(equalToConstant: height)
			])
		}
	}

	private class CustomCursorView: NSView {
		var cursor: NSCursor = .arrow

		override func resetCursorRects() {
			super.resetCursorRects()
			addCursorRect(bounds, cursor: cursor)
		}
	}

	private struct DragHandleView: View {
		var body: some View {
			ZStack {
				Color.clear.contentShape(Rectangle())
				RoundedRectangle(cornerRadius: 2.0)
					.fill(Color.white)
					.frame(width: 128.0, height: 4)
					.padding()
			}
			.pointerStyle(.rowResize)
		}
	}
}
