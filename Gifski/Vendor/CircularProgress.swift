// Vendored from: https://github.com/sindresorhus/CircularProgress
import Cocoa

@IBDesignable
public final class CircularProgress: NSView {
	private var lineWidth: Double = 2
	// TODO: Remove the closure here when targeting Swift 5
	private lazy var radius = { bounds.width < bounds.height ? bounds.midX * 0.8 : bounds.midY * 0.8 }()
	private var _progress: Double = 0
	private var progressObserver: NSKeyValueObservation?
	private var finishedObserver: NSKeyValueObservation?
	private var cancelledObserver: NSKeyValueObservation?
	private var indeterminateObserver: NSKeyValueObservation?

	private lazy var backgroundCircle = with(CAShapeLayer.circle(radius: Double(radius), center: bounds.center)) {
		$0.frame = bounds
		$0.fillColor = nil
		$0.lineWidth = CGFloat(lineWidth) / 2
	}

	private lazy var progressCircle = with(ProgressCircleShapeLayer(radius: Double(radius), center: bounds.center)) {
		$0.lineWidth = CGFloat(lineWidth)
	}

	private lazy var progressLabel = with(CATextLayer(text: "0%")) {
		$0.color = color
		$0.fontSize = bounds.width < bounds.height ? bounds.width * 0.2 : bounds.height * 0.2
		$0.frame = CGRect(x: 0, y: 0, width: bounds.width, height: $0.preferredFrameSize().height)
		$0.position = CGPoint(x: bounds.midX, y: bounds.midY)
		$0.anchorPoint = CGPoint(x: 0.5, y: 0.5)
		$0.alignmentMode = .center
		$0.font = NSFont.helveticaNeueLight // Not using the system font as it has too much number width variance
		$0.isHidden = true
	}

	internal lazy var indeterminateCircle = with(IndeterminateShapeLayer(radius: Double(radius), center: bounds.center)) {
		$0.lineWidth = CGFloat(lineWidth)
	}

	private lazy var cancelButton = with(CustomButton.circularButton(title: "╳", radius: Double(radius), center: bounds.center)) {
		$0.textColor = color
		$0.backgroundColor = color.with(alpha: 0.1)
		$0.activeBackgroundColor = color
		$0.borderWidth = 0
		$0.isHidden = true
		$0.onAction = { _ in
			self.cancelProgress()
		}
	}

	private var originalColor: NSColor = .controlAccentColorPolyfill
	private var _color: NSColor = .controlAccentColorPolyfill
	/**
	Color of the circular progress view.

	Defaults to the user's accent color. For High Sierra and below it uses a fallback color.
	*/
	@IBInspectable public var color: NSColor {
		get {
			return _color
		}
		set {
			_color = newValue
			originalColor = newValue

			needsDisplay = true
		}
	}

	/**
	Show `✔` instead `100%`.
	*/
	@IBInspectable public var showCheckmarkAtHundredPercent: Bool = true

	/**
	The progress value in the range `0...1`.

	- Note: The value will be clamped to `0...1`.
	- Note: Can be set from a background thread.
	*/
	@IBInspectable public var progress: Double {
		get {
			return _progress
		}
		set {
			_progress = newValue.clamped(to: 0...1)

			// swiftlint:disable:next trailing_closure
			CALayer.animate(duration: 0.5, timingFunction: .easeOut, animations: {
				self.progressCircle.progress = self._progress
			})

			DispatchQueue.main.async {
				self.progressLabel.isHidden = self.progress == 0 && self.isIndeterminate ? self.cancelButton.isHidden : !self.cancelButton.isHidden
			}

			if !progressLabel.isHidden {
				progressLabel.string = "\(Int(_progress * 100))%"
			}

			if _progress == 1 {
				isFinished = true
			}

			// TODO: Figure out why I need to flush here to get the label to update in `Gifski.app`.
			CATransaction.flush()
		}
	}

	private var _isFinished = false
	/**
	Returns whether the progress is finished.
	*/
	@IBInspectable public private(set) var isFinished: Bool {
		get {
			if let progressInstance = progressInstance {
				return progressInstance.isFinished
			}

			return _isFinished
		}
		set {
			_isFinished = newValue

			if _isFinished {
				isIndeterminate = false

				if showCheckmarkAtHundredPercent {
					progressLabel.string = "✓"
				}
			}
		}
	}

	/**
	Let a `Progress` instance update the `progress` for you.
	*/
	public var progressInstance: Progress? {
		didSet {
			if let progressInstance = progressInstance {
				progressObserver = progressInstance.observe(\.fractionCompleted) { sender, _ in
					guard !self.isCancelled && !sender.isFinished else {
						return
					}

					self.progress = sender.fractionCompleted
				}

				finishedObserver = progressInstance.observe(\.isFinished) { sender, _ in
					guard !self.isCancelled && sender.isFinished else {
						return
					}

					self.progress = 1
				}

				cancelledObserver = progressInstance.observe(\.isCancelled) { sender, _ in
					self.isCancelled = sender.isCancelled
				}

				indeterminateObserver = progressInstance.observe(\.isIndeterminate) { sender, _ in
					self.isIndeterminate = sender.isIndeterminate
				}

				isCancellable = progressInstance.isCancellable

				isIndeterminate = progressInstance.isIndeterminate
			}
		}
	}

	override public init(frame: CGRect) {
		super.init(frame: frame)
		commonInit()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}

	override public func prepareForInterfaceBuilder() {
		super.prepareForInterfaceBuilder()
		commonInit()
		progressCircle.progress = _progress
	}

	/**
	Initialize the progress view with a width/height of the given `size`.
	*/
	public convenience init(size: Double) {
		self.init(frame: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
	}

	override public func updateLayer() {
		updateColors()
	}

	private func updateColors() {
		let duration = 0.2
		backgroundCircle.animate(color: color.with(alpha: 0.5).cgColor, keyPath: #keyPath(CAShapeLayer.strokeColor), duration: duration)

		progressCircle.animate(color: color.cgColor, keyPath: #keyPath(CAShapeLayer.strokeColor), duration: duration)
		progressLabel.animate(color: color.cgColor, keyPath: #keyPath(CATextLayer.foregroundColor), duration: duration)

		indeterminateCircle.animate(color: color.cgColor, keyPath: #keyPath(CAShapeLayer.strokeColor), duration: duration)

		cancelButton.textColor = color
		cancelButton.backgroundColor = color.with(alpha: 0.1)
		cancelButton.activeBackgroundColor = color

		if indeterminateCircle.animation(forKey: "rotate") == nil {
			indeterminateCircle.add(CABasicAnimation.rotate, forKey: "rotate")
		}
	}

	private func commonInit() {
		wantsLayer = true
		layer?.addSublayer(backgroundCircle)
		layer?.addSublayer(indeterminateCircle)
		layer?.addSublayer(progressCircle)
		layer?.addSublayer(progressLabel)

		addSubview(cancelButton)

		progressCircle.isHidden = isIndeterminate
		indeterminateCircle.isHidden = !isIndeterminate
	}

	/**
	Reset the progress back to zero without animating.
	*/
	public func resetProgress() {
		alphaValue = 1

		_color = originalColor
		_progress = 0

		_isFinished = false
		_isCancelled = false
		isIndeterminate = false

		progressCircle.resetProgress()
		progressLabel.string = "0%"

		needsDisplay = true
	}

	/**
	Cancels `Progress` if it's set and prevents further updates.
	*/
	public func cancelProgress() {
		guard isCancellable else {
			return
		}

		guard let progressInstance = progressInstance else {
			isCancelled = true
			return
		}

		progressInstance.cancel()
	}

	/**
	Triggers when the progress was cancelled succesfully.
	*/
	public var onCancelled: (() -> Void)?

	private var _isCancellable = false
	/**
	If the progress view is cancellable it shows the cancel button.
	*/
	@IBInspectable public var isCancellable: Bool {
		get {
			if let progressInstance = progressInstance {
				return progressInstance.isCancellable
			}

			return _isCancellable
		}
		set {
			_isCancellable = newValue
			updateTrackingAreas()
		}
	}

	private var _isCancelled = false
	/**
	Returns whether the progress has been cancelled.
	*/
	@IBInspectable public private(set) var isCancelled: Bool {
		get {
			if let progressInstance = progressInstance {
				return progressInstance.isCancelled
			}

			return _isCancelled
		}
		set {
			_isCancelled = newValue

			if newValue {
				onCancelled?()
				visualizeCancelledStateIfNecessary()
				isIndeterminate = false
			}
		}
	}

	/**
	Determines whether to visualize changing into the cancelled state.
	*/
	public var visualizeCancelledState: Bool = true

	/**
	Supply the base color to use for displaying the cancelled state.
	*/
	public var cancelledStateColorHandler: ((NSColor) -> NSColor)?

	private func visualizeCancelledStateIfNecessary() {
		guard visualizeCancelledState else {
			return
		}

		if let colorHandler = cancelledStateColorHandler {
			_color = colorHandler(originalColor)
		} else {
			_color = originalColor.adjusting(saturation: -0.4, brightness: -0.2)
			alphaValue = 0.7
		}

		needsDisplay = true
	}

	private var trackingArea: NSTrackingArea?

	override public func updateTrackingAreas() {
		if let oldTrackingArea = trackingArea {
			removeTrackingArea(oldTrackingArea)
		}

		guard isCancellable else {
			return
		}

		let newTrackingArea = NSTrackingArea(
			rect: cancelButton.frame,
			options: [
				.mouseEnteredAndExited,
				.activeInActiveApp
			],
			owner: self,
			userInfo: nil
		)

		addTrackingArea(newTrackingArea)
		trackingArea = newTrackingArea
	}

	override public func mouseEntered(with event: NSEvent) {
		guard isCancellable else {
			super.mouseEntered(with: event)
			return
		}

		progressLabel.isHidden = true
		cancelButton.fadeIn()
	}

	override public func mouseExited(with event: NSEvent) {
		guard isCancellable else {
			super.mouseExited(with: event)
			return
		}

		progressLabel.isHidden = isIndeterminate && progress == 0
		cancelButton.isHidden = true
	}

	private var _isIndeterminate = false
	/**
	Returns whether the progress is indeterminate.
	*/
	@IBInspectable public var isIndeterminate: Bool {
		get {
			if let progressInstance = progressInstance {
				return progressInstance.isIndeterminate
			}

			return _isIndeterminate
		}
		set {
			willChangeValue(for: \.isIndeterminate)
			_isIndeterminate = newValue
			didChangeValue(for: \.isIndeterminate)

			if _isIndeterminate {
				startIndeterminateState()
			} else {
				stopIndeterminateState()
			}
		}
	}

	private func startIndeterminateState() {
		progressCircle.isHidden = true
		indeterminateCircle.isHidden = false

		progressLabel.isHidden = progress == 0 && isIndeterminate && cancelButton.isHidden
	}

	private func stopIndeterminateState() {
		indeterminateCircle.isHidden = true
		progressCircle.isHidden = false

		progressLabel.isHidden = !cancelButton.isHidden
	}
}
