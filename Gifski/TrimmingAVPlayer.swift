import AVKit
import SwiftUI

struct TrimmingAVPlayer: NSViewControllerRepresentable {
	typealias NSViewControllerType = TrimmingAVPlayerViewController

	let asset: AVAsset
	var controlsStyle = AVPlayerViewControlsStyle.inline
	var loopPlayback = false
	var bouncePlayback = false
	var speed = 1.0
	@Binding var cropRect: CropRect
	var showCropRectUnderTrim = false
	var timeRangeDidChange: ((ClosedRange<Double>) -> Void)?

	func makeNSViewController(context: Context) -> NSViewControllerType {
		.init(
			cropRect: $cropRect,
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
		nsViewController.showCropRectUnderTrim = showCropRectUnderTrim
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
	@Binding var cropRect: CropRect

	private final class CropRectHolder: ObservableObject  {
		@Published var playerSize: CGSize = .zero
	}


	private var underTrimCropRectHolder = CropRectHolder()

	private struct UnderTrimCropOverlay: View {
		@Binding var cropRect: CropRect
		/// Turning  of linter so I can use the default constructor
		@StateObject var cropRectHolder: CropRectHolder // swiftlint:disable:this private_swiftui_state
		var body: some View {
			CropOverlayView(
				cropRect: $cropRect,
				editable: true
			)
			.frame(
				width: cropRectHolder.playerSize.width,
				height: cropRectHolder.playerSize.height
			)
		}
	}

	private var underTrimCropOverlayView: NSHostingView<UnderTrimCropOverlay>!

	var playerView: TrimmingAVPlayerView { view as! TrimmingAVPlayerView }

	fileprivate var showCropRectUnderTrim = false {
		didSet {
			Task {
				@MainActor in
				if let trimmerDragViews = self.getTrimmerDragViews() {
					if self.showCropRectUnderTrim {
						trimmerDragViews.showDrag()
					} else {
						trimmerDragViews.hideDrag()
					}
				}

				underTrimCropRectHolder.playerSize = playerView.videoBounds.size
				guard showCropRectUnderTrim else {
					underTrimCropOverlayView.removeFromSuperview()
					return
				}
				playerView.contentOverlayView?.addSubview(underTrimCropOverlayView)

				underTrimCropOverlayView.translatesAutoresizingMaskIntoConstraints = false
				NSLayoutConstraint.deactivate(underTrimCropOverlayView.constraints)

				guard let videoBounds = playerView.contentOverlayView?.bounds else {
					return
				}
				NSLayoutConstraint.activate([
					underTrimCropOverlayView.leadingAnchor.constraint(equalTo: playerView.contentOverlayView!.leadingAnchor, constant: videoBounds.origin.x),
					underTrimCropOverlayView.topAnchor.constraint(equalTo: playerView.contentOverlayView!.topAnchor, constant: videoBounds.origin.y),
					underTrimCropOverlayView.widthAnchor.constraint(equalToConstant: videoBounds.size.width),
					underTrimCropOverlayView.heightAnchor.constraint(equalToConstant: videoBounds.size.height)
				])
			}
		}
	}
	/// Can't use lazy here because at start this will be null
	/// before the player is initialized (there won't be an AVTrimView)
	private var _trimmerDragViews: TrimmerDragViews?

	private func getTrimmerDragViews() -> TrimmerDragViews? {
		if let _trimmerDragViews {
			return _trimmerDragViews
		}
		guard let avTrimView = (playerView.firstSubview(deep: true) { $0.simpleClassName == "AVTrimView" })?.superview,
		let avTrimViewParent = avTrimView.superview?.superview else {
			return nil
		}
		_trimmerDragViews = TrimmerDragViews(avTrimView: avTrimView, avTrimViewParent: avTrimViewParent, showDragNow: false)
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
		cropRect: Binding<CropRect>,
		playerItem: AVPlayerItem,
		controlsStyle: AVPlayerViewControlsStyle = .inline,
		timeRangeDidChange: ((ClosedRange<Double>) -> Void)? = nil
	) {
		self._cropRect = cropRect
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
		underTrimCropOverlayView = NSHostingView(rootView: UnderTrimCropOverlay(
			cropRect: $cropRect,
			cropRectHolder: self.underTrimCropRectHolder
		))
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
	private var cursor: CustomCursorView
	private var avTrimViewParent: NSView
	private var drawHandleView: NSHostingView<DragHandleView>

	var canDrag = false

	static let originalHeight = 64.0
	static let newHeight = 87.0

	init(avTrimView: NSView, avTrimViewParent: NSView, showDragNow: Bool){
		self.avTrimView = avTrimView
		self.avTrimViewParent = avTrimViewParent
		self.cursor = CustomCursorView()
		self.drawHandleView = NSHostingView(rootView: DragHandleView())


		let parent = avTrimViewParent.superview

		avTrimViewParent.removeFromSuperview()


		cursor.translatesAutoresizingMaskIntoConstraints = false
		cursor.addSubview(avTrimViewParent)
		parent?.addSubview(cursor)

		NSLayoutConstraint.activate([
			avTrimViewParent.leadingAnchor.constraint(equalTo: cursor.leadingAnchor, constant: 0),
			avTrimViewParent.bottomAnchor.constraint(equalTo: cursor.bottomAnchor, constant: 0),
			avTrimViewParent.widthAnchor.constraint(equalTo: cursor.widthAnchor, constant: 0),
			avTrimViewParent.heightAnchor.constraint(equalTo: cursor.heightAnchor, constant: 0)
		])

		NSLayoutConstraint.activate([
			cursor.leadingAnchor.constraint(equalTo: parent!.leadingAnchor, constant: 6.0),
			cursor.bottomAnchor.constraint(equalTo: parent!.bottomAnchor, constant: -6.0),
			cursor.widthAnchor.constraint(equalToConstant: 748.0)
		])
		if showDragNow {
			self.showDrag()
		} else {
			self.hideDrag()
		}

		let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
		panGesture.delaysPrimaryMouseButtonEvents = false
		cursor.addGestureRecognizer(panGesture)
	}

	func showDrag() {
		canDrag = true

		cursor.addSubview(drawHandleView)
		drawHandleView.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			drawHandleView.leadingAnchor.constraint(equalTo: cursor.leadingAnchor, constant: 0),
			drawHandleView.trailingAnchor.constraint(equalTo: cursor.trailingAnchor, constant: 0),
			drawHandleView.topAnchor.constraint(equalTo: cursor.topAnchor, constant: 6),
			drawHandleView.heightAnchor.constraint(equalToConstant: 17.0)
		])

		NSLayoutConstraint.deactivate(
			cursor.constraints.filter { $0.firstAttribute == .height && $0.firstItem as? NSView == cursor }
		)
		NSLayoutConstraint.activate([
			cursor.heightAnchor.constraint(equalToConstant: Self.newHeight)
		])
		if let topConstraint = avTrimView.superview?.constraints.first(where: {
			($0.firstItem as? NSView) == avTrimView && $0.firstAttribute == .top
		}) {
			topConstraint.constant = Self.newHeight - Self.originalHeight
		}
	}
	func hideDrag() {
		canDrag = false

		self.drawHandleView.removeFromSuperview()


		if let bottomConstraint = cursor.superview?.constraints.first(where: {
			$0.firstItem as? NSView == cursor && $0.firstAttribute == .bottom
		}) {
			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0.25 // Set the animation duration (in seconds)
				context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
				bottomConstraint.animator().constant = -6.0
			}
		}

		NSLayoutConstraint.deactivate(
			cursor.constraints.filter { $0.firstAttribute == .height && $0.firstItem as? NSView == cursor }
		)

		NSLayoutConstraint.activate([
			cursor.heightAnchor.constraint(equalToConstant: Self.originalHeight)
		])

		if let topConstraint = avTrimView.superview?.constraints.first(where: {
			($0.firstItem as? NSView) == avTrimView && $0.firstAttribute == .top
		}) {
			topConstraint.constant = 0
		}
	}

	@objc private func handleDrag(_ gesture: NSPanGestureRecognizer) {
		guard canDrag,
			gesture.state == .began || gesture.state == .changed,
			let view = gesture.view,
			let superview = view.superview,
			let bottomConstraint = superview.constraints.first(where: { $0.firstItem as? NSView == view && $0.firstAttribute == .bottom }) else {
			return
		}

		// Get the mouse location in the superview's coordinate space
    	let mouseLocation = gesture.location(in: superview)
		if !superview.bounds.contains(mouseLocation) {
			return
		}

		let translation = gesture.translation(in: superview)
		let newBottom = bottomConstraint.constant - translation.y
		let minBottom = -superview.bounds.height + view.frame.height
		bottomConstraint.constant = max(minBottom, min(newBottom, 0))
		gesture.setTranslation(.zero, in: superview)
	}

	private class CustomCursorView: NSView {
		var cursor: NSCursor = .arrow

		override func resetCursorRects() {
			super.resetCursorRects()
			addCursorRect(
				self.bounds,
				cursor: cursor
			)
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
