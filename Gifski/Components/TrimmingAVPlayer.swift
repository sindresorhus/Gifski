import AVKit
import SwiftUI

struct TrimmingAVPlayer: NSViewControllerRepresentable {
	typealias NSViewControllerType = TrimmingAVPlayerViewController

	@Environment(\.colorScheme) private var colorScheme

	let asset: AVAsset
	let shouldShowPreview: Bool
	let fullPreviewState: FullPreviewGenerationEvent
	var controlsStyle = AVPlayerViewControlsStyle.inline
	var loopPlayback = false
	var bouncePlayback = false
	var speed = 1.0
	var overlay: NSView?
	var isPlayPauseButtonEnabled = true
	var isTrimmerCollapsible = false
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
			let item = AVPlayerItem(asset: asset)
			forceAVPlayerToRedraw(item: item)
			item.playbackRange = nsViewController.currentItem.playbackRange
			nsViewController.currentItem = item
		}

		// Always update video composition based on preview state.
		// When preview is ON, use custom compositor. When OFF, clear it so AVPlayer handles rotation.
		let currentItem = nsViewController.currentItem
		if
			currentItem.videoComposition == nil,
			shouldShowPreview,
			fullPreviewState.canShowPreview
		{
			forceAVPlayerToRedraw(item: currentItem)
		}

		let didUpdatePreviewState = updatePreviewState(nsViewController)
		forceAVPlayerToRedraw(item: currentItem, forceRedraw: didUpdatePreviewState)

		nsViewController.loopPlayback = loopPlayback
		nsViewController.bouncePlayback = bouncePlayback
		nsViewController.player.defaultRate = Float(speed)
		if nsViewController.player.rate != 0 {
			nsViewController.player.rate = nsViewController.player.rate > 0 ? Float(speed) : -Float(speed)
		}
		nsViewController.overlay = overlay
		nsViewController.isTrimmerCollapsible = isTrimmerCollapsible
		nsViewController.isPlayPauseButtonEnabled = isPlayPauseButtonEnabled
	}

	/**
	Update the preview state.

	- Returns: True if state was updated and needs a redraw, false otherwise.
	*/
	func updatePreviewState(_ controller: NSViewControllerType) -> Bool {
		guard
			let previewVideoCompositor = controller.currentItem.customVideoCompositor as? PreviewVideoCompositor
		else {
			return false
		}

		let previewCheckerboardParams = CompositePreviewFragmentUniforms(
			isDarkMode: colorScheme.isDark,
			videoBounds: controller.playerView.videoBounds
		)

		return previewVideoCompositor.updateState(
			state: .init(
				shouldShowPreview: shouldShowPreview,
				fullPreviewState: fullPreviewState,
				previewCheckerboardParams: previewCheckerboardParams
			)
		)
	}

	/**
	Sets or clears the video composition based on preview state.

	When preview is OFF, we don't use the custom compositor so AVPlayer handles rotation via `preferredTransform` normally.
	When preview is ON, we use the custom compositor which renders the preview overlay.
	*/
	func forceAVPlayerToRedraw(item: AVPlayerItem, forceRedraw: Bool = false) {
		guard let assetVideoComposition = (asset as? PreviewableComposition)?.videoComposition else {
			return
		}

		let shouldUsePreviewCompositor = shouldShowPreview && fullPreviewState.canShowPreview
		let targetVideoComposition = shouldUsePreviewCompositor ? assetVideoComposition : nil
		let hasCompositionStateChanged = (item.videoComposition != nil) != (targetVideoComposition != nil)
		guard
			forceRedraw || hasCompositionStateChanged
		else {
			return
		}

		item.videoComposition = targetVideoComposition
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
	private var currentItemDurationRange: ClosedRange<Double>?

	private var overlayContainer: OverlayContainerView?

	fileprivate var overlay: NSView? {
		didSet {
			guard oldValue != overlay else {
				return
			}

			oldValue?.removeFromSuperview()
			placeOverlay()
		}
	}

	fileprivate var isTrimmerCollapsible = false {
		didSet {
			guard isTrimmerCollapsible != oldValue else {
				return
			}

			if !isTrimmerCollapsible {
				overlayContainer?.removeFromSuperview()
				overlayContainer = nil
			}

			// Place overlay first so the container is created before the toggle button,
			// ensuring the button is always on top in the z-order.
			placeOverlay()
			collapsibleTrimmer?.isCollapsible = isTrimmerCollapsible
		}
	}

	/**
	Places the overlay in the correct layer based on crop mode.

	When cropping, the overlay goes on `playerView` (via a container) so crop handles sit above the player controls. Hit testing passes through to the trimmer area.

	When not cropping, the overlay goes on `contentOverlayView` (behind controls) so the trimmer is fully accessible.
	*/
	private func placeOverlay() {
		guard let overlay else {
			return
		}

		overlay.removeFromSuperview()
		overlay.removeConstraints(overlay.constraints)

		if isTrimmerCollapsible {
			if overlayContainer == nil {
				let container = OverlayContainerView()
				container.passthroughView = _collapsibleTrimmer?.trimmerWrapper
				playerView.addSubview(container)
				container.translatesAutoresizingMaskIntoConstraints = false
				NSLayoutConstraint.activate([
					container.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
					container.topAnchor.constraint(equalTo: playerView.topAnchor),
					container.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
					container.bottomAnchor.constraint(equalTo: playerView.bottomAnchor)
				])
				overlayContainer = container
			}

			guard let overlayContainer else {
				return
			}

			overlayContainer.addSubview(overlay)
			overlay.translatesAutoresizingMaskIntoConstraints = false

			let videoBounds = playerView.videoBounds
			NSLayoutConstraint.activate([
				overlay.leadingAnchor.constraint(equalTo: overlayContainer.leadingAnchor, constant: videoBounds.origin.x),
				overlay.topAnchor.constraint(equalTo: overlayContainer.topAnchor, constant: videoBounds.origin.y),
				overlay.widthAnchor.constraint(equalToConstant: videoBounds.size.width),
				overlay.heightAnchor.constraint(equalToConstant: videoBounds.size.height)
			])
		} else {
			guard let contentOverlayView = playerView.contentOverlayView else {
				return
			}

			let videoBounds = playerView.videoBounds

			contentOverlayView.addSubview(overlay)
			overlay.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				overlay.leadingAnchor.constraint(equalTo: contentOverlayView.leadingAnchor, constant: videoBounds.origin.x),
				overlay.topAnchor.constraint(equalTo: contentOverlayView.topAnchor, constant: videoBounds.origin.y),
				overlay.widthAnchor.constraint(equalToConstant: videoBounds.size.width),
				overlay.heightAnchor.constraint(equalToConstant: videoBounds.size.height)
			])
		}
	}

	fileprivate var isPlayPauseButtonEnabled = true {
		didSet {
			guard isPlayPauseButtonEnabled != oldValue else {
				return
			}

			playerView.setPlayPauseButton(isEnabled: isPlayPauseButtonEnabled)
		}
	}

	var playerView: TrimmingAVPlayerView { view as! TrimmingAVPlayerView }

	// We cannot use lazy here because at start this will be `nil` before the player is initialized (there won't be an AVTrimView).
	private var _collapsibleTrimmer: CollapsibleTrimmer?

	private var collapsibleTrimmer: CollapsibleTrimmer? {
		if let _collapsibleTrimmer {
			return _collapsibleTrimmer
		}

		// Needed so that it will hide the trimmer when it is outside the view. This must be done now (as opposed to `viewDidLoad`) because layer is nil in `viewDidLoad`.
		playerView.layer?.masksToBounds = true

		guard
			let avTrimView = (playerView.firstSubview(deep: true) { $0.simpleClassName == "AVTrimView" })?.superview,
			let avTrimViewParent = avTrimView.superview?.superview
		else {
			return nil
		}

		let trimmer = CollapsibleTrimmer(
			avTrimView: avTrimView,
			avTrimViewParent: avTrimViewParent,
			playerView: playerView
		)

		overlayContainer?.passthroughView = trimmer.trimmerWrapper

		_collapsibleTrimmer = trimmer
		return trimmer
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

				onNewDurationRange(durationRange: $0.durationRange)

				// This is here as it needs to be refreshed when the current item changes.
				playerView.observeTrimmedTimeRange { [weak self] timeRange in
					self?.timeRange = timeRange
					self?.timeRangeDidChange?(timeRange)
				}
			}
			.store(in: &cancellables)
	}

	func onNewDurationRange(durationRange newItemDurationRange: ClosedRange<Double>?) {
		guard let newItemDurationRange else {
			currentItemDurationRange = nil
			return
		}
		defer {
			currentItemDurationRange = newItemDurationRange
		}
		guard
			let timeRange,
			let currentItemDurationRange
		else {
			self.timeRange = newItemDurationRange
			timeRangeDidChange?(newItemDurationRange)
			return
		}
		let newTimeRange = timeRange.translated(from: currentItemDurationRange, to: newItemDurationRange)
		self.timeRange = newTimeRange
		timeRangeDidChange?(newTimeRange)
	}
}

final class TrimmingAVPlayerView: AVPlayerView {
	private var timeRangeCancellable: AnyCancellable?
	private var trimmingCancellable: AnyCancellable?
	private var readyForDisplayCancellable: AnyCancellable?
	private var checkerboardVideoBounds: CGRect?

	/**
	The minimum duration the trimmer can be set to.
	*/
	var minimumTrimDuration = 0.1

	deinit {
		print("TrimmingAVPlayerView - DEINIT")
	}

	override func layout() {
		super.layout()

		updateCheckerboardViewIfNeeded()
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
				hideTrimButtons()
				window?.makeFirstResponder(self)
			} catch is CancellationError {
				// Task was cancelled, ignore.
			} catch {
				assertionFailure("Failed to activate trimming: \(error)")
			}
		}
		.toCancellable

		observeReadyForDisplay()
	}

	private func observeReadyForDisplay() {
		readyForDisplayCancellable = publisher(for: \.isReadyForDisplay)
			.first(where: \.self)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
				self?.updateCheckerboardViewIfNeeded()
			}
	}

	fileprivate func setPlayPauseButton(isEnabled: Bool) {
		guard
			let avTrimView = firstSubview(deep: true, where: { $0.simpleClassName == "AVTrimView" }),
			let superview = avTrimView.superview
		else {
			return
		}

		let playPauseButton = superview
			.subviews
			.first { $0 != avTrimView }?
			.subviews
			.first {
				guard
					let button = ($0 as? NSButton),
					button.action?.description == "playPauseButtonPressed:"
				else {
					return false
				}

				return true
			} as? NSButton

		guard let playPauseButton else {
			return
		}

		playPauseButton.isEnabled = isEnabled
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
		if #available(macOS 27, *) {
			// The play button is now a direct sibling, and the trailing constraint points to a separate container for Trim and Cancel.
			guard
				let constraint = superview.constraints.first(where: {
					($0.secondItem as? NSView) == avTrimView && $0.secondAttribute == .trailing
				}),
				let buttonContainer = constraint.firstItem as? NSView
			else {
				return
			}

			buttonContainer.isHidden = true
			superview.removeConstraint(constraint)
			constraint.changing(firstAttribute: .trailing).isActive = true
			return
		}

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

	private func updateCheckerboardViewIfNeeded() {
		guard let contentOverlayView else {
			return
		}

		// Large videos can become ready before AVPlayer has computed `videoBounds`. Wait for a real rect so the checkerboard does not cover the whole player.
		let clearRect = videoBounds
		guard !clearRect.isEmpty else {
			return
		}

		let existingCheckerboardViews = contentOverlayView.subviews.filter { $0.identifier == Self.checkerboardViewIdentifier }
		let needsNewCheckerboardView = clearRect != checkerboardVideoBounds || existingCheckerboardViews.isEmpty
		guard needsNewCheckerboardView else {
			return
		}

		for subview in existingCheckerboardViews {
			subview.removeFromSuperview()
		}

		let overlayView = NSHostingView(rootView: CheckerboardView(clearRect: clearRect))
		overlayView.identifier = Self.checkerboardViewIdentifier
		contentOverlayView.addSubview(overlayView)
		overlayView.constrainEdgesToSuperview()
		checkerboardVideoBounds = clearRect
	}

	private static let checkerboardViewIdentifier = NSUserInterfaceItemIdentifier("CheckerboardView")

	/**
	Prevent user from dismissing trimming view.
	*/
	override func cancelOperation(_ sender: Any?) {}
}

/**
Passes through hits in the area occupied by `passthroughView` (the trimmer) so both the crop overlay and trimmer can coexist. When the trimmer is collapsed (off-screen), its frame is outside the visible area and all hits go to the crop overlay as normal.
*/
private class OverlayContainerView: NSView {
	weak var passthroughView: NSView?

	override func hitTest(_ point: CGPoint) -> NSView? {
		guard !subviews.isEmpty else {
			return nil
		}

		if
			let passthroughView,
			let passthroughParent = passthroughView.superview
		{
			let convertedPoint = convert(point, to: passthroughParent)
			if passthroughView.frame.contains(convertedPoint) {
				return nil
			}
		}

		// Only claim hits that land on a subview (the overlay), not on empty container space.
		// This ensures the toggle button behind the container remains clickable.
		let result = super.hitTest(point)
		return result === self ? nil : result
	}
}

@MainActor
private class CollapsibleTrimmer {
	private let avTrimView: NSView
	let trimmerWrapper: NSView
	private let avTrimViewParent: NSView
	private weak var playerView: NSView?
	private var toggleButton: NSHostingView<ToggleButtonView>
	private var isCollapsed = false
	private let savedConstraints: SavedConstraints

	var isCollapsible = false {
		didSet {
			guard isCollapsible != oldValue else {
				return
			}

			if isCollapsible {
				addToggleButton()
				setCollapsed(true)
			} else {
				removeToggleButton()
				setCollapsed(false)
			}
		}
	}

	init(avTrimView: NSView, avTrimViewParent: NSView, playerView: NSView) {
		self.avTrimView = avTrimView
		self.avTrimViewParent = avTrimViewParent
		self.playerView = playerView
		self.trimmerWrapper = NSView()
		self.savedConstraints = SavedConstraints(avTrimViewParent: avTrimViewParent)
		self.toggleButton = NSHostingView(rootView: ToggleButtonView(isCollapsed: false) {})

		reparentTrimmer()
		updateToggleButton()
	}

	/**
	Remove the `avTrimViewParent` from its old location in the view hierarchy and wrap it in our `trimmerWrapper`.
	*/
	private func reparentTrimmer() {
		guard let oldSuperview = avTrimViewParent.superview else {
			return
		}

		avTrimViewParent.removeFromSuperview()

		trimmerWrapper.translatesAutoresizingMaskIntoConstraints = false
		trimmerWrapper.addSubview(avTrimViewParent)
		oldSuperview.addSubview(trimmerWrapper)

		avTrimViewParent.constrainEdgesToSuperview()
		savedConstraints.apply(to: trimmerWrapper, in: oldSuperview)
	}

	private func setCollapsed(_ collapsed: Bool) {
		isCollapsed = collapsed
		updateToggleButton()

		if collapsed {
			bottomConstraint?.animate(to: savedConstraints.height, duration: .seconds(0.3)) { [weak self] in
				guard
					let self,
					isCollapsed
				else {
					return
				}

				avTrimView.isHidden = true
			}
		} else {
			avTrimView.isHidden = false
			bottomConstraint?.animate(to: savedConstraints.bottomOffset, duration: .seconds(0.3))
		}
	}

	private func updateToggleButton() {
		toggleButton.rootView = ToggleButtonView(isCollapsed: isCollapsed) { [weak self] in
			guard let self else {
				return
			}

			setCollapsed(!isCollapsed)
		}
	}

	private func addToggleButton() {
		guard let playerView else {
			return
		}

		// Added to playerView directly so it sits above the crop overlay.
		playerView.addSubview(toggleButton)
		toggleButton.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			toggleButton.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
			toggleButton.bottomAnchor.constraint(equalTo: trimmerWrapper.topAnchor),
			toggleButton.widthAnchor.constraint(equalToConstant: 34),
			toggleButton.heightAnchor.constraint(equalToConstant: 22)
		])
	}

	private func removeToggleButton() {
		toggleButton.removeFromSuperview()
	}

	private lazy var bottomConstraint: NSLayoutConstraint? = trimmerWrapper.getConstraintFromSuperview(attribute: .bottom)

	/**
	Captures the trimmer's original constraints before reparenting, so the wrapper can be placed identically.
	*/
	@MainActor
	private struct SavedConstraints {
		let bottomOffset: Double
		let leadingOffset: Double
		let trailingOffset: Double
		let height: Double

		init(avTrimViewParent: NSView) {
			self.bottomOffset = -(avTrimViewParent.getConstraintConstantFromSuperView(attribute: .bottom) ?? 6.0)
			self.leadingOffset = avTrimViewParent.getConstraintConstantFromSuperView(attribute: .leading) ?? 6.0
			self.trailingOffset = -(avTrimViewParent.getConstraintConstantFromSuperView(attribute: .trailing) ?? 6.0)
			self.height = avTrimViewParent.getConstraintConstantFromSuperView(attribute: .height) ?? 64.0
		}

		func apply(to newView: NSView, in superview: NSView) {
			NSLayoutConstraint.activate([
				newView.leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: leadingOffset),
				newView.bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: bottomOffset),
				newView.trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: trailingOffset),
				newView.heightAnchor.constraint(equalToConstant: height)
			])
		}
	}

	private struct ToggleButtonView: View {
		@State private var isHovered = false

		let isCollapsed: Bool
		let action: () -> Void

		var body: some View {
			Button("Toggle Trimmer", systemImage: isCollapsed ? "chevron.compact.up" : "chevron.compact.down", action: action)
				.labelStyle(.iconOnly)
				.font(.system(size: 16, weight: .bold))
				.foregroundStyle(.white.opacity(0.8))
				.fillFrame()
				.contentShape(.rect)
				.buttonStyle(.plain)
				.background(
					Capsule()
						.fill(.white.opacity(isHovered ? 0.2 : 0.05))
				)
				.onHover {
					isHovered = $0
				}
		}
	}
}
