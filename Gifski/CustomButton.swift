import Cocoa

// TODO(sindresorhus): I plan to extract this into a reusable package when it's more mature.

extension CALayer {
	// TODO: Find a way to use a strongly-typed KeyPath here.
	// TODO: Accept NSColor instead of CGColor.
	func animate(color: CGColor, keyPath: String, duration: Double) {
		guard (value(forKey: keyPath) as! CGColor?) != color else {
			return
		}

		let animation = CABasicAnimation(keyPath: keyPath)
		animation.fromValue = value(forKey: keyPath)
		animation.toValue = color
		animation.duration = duration
		animation.fillMode = .forwards
		animation.isRemovedOnCompletion = false
		add(animation, forKey: keyPath)
		setValue(color, forKey: keyPath)
	}
}

extension CGPoint {
	func rounded(_ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> CGPoint {
		return CGPoint(x: x.rounded(rule), y: y.rounded(rule))
	}
}

extension CGRect {
	func roundedOrigin(_ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> CGRect {
		var rect = self
		rect.origin = rect.origin.rounded(rule)
		return rect
	}
}

extension CGSize {
	/// Returns a CGRect with `self` centered in it.
	func centered(in rect: CGRect) -> CGRect {
		return CGRect(
			x: (rect.width - width) / 2,
			y: (rect.height - height) / 2,
			width: width,
			height: height
		)
	}
}

// TODO: Add padding option
@IBDesignable
open class CustomButton: NSButton {
	private let titleLayer = CATextLayer()
	private var isMouseDown = false

	static func circularButton(title: String, radius: Double, center: CGPoint) -> CustomButton {
		return with(CustomButton()) {
			$0.title = title
			$0.frame = CGRect(x: Double(center.x) - radius, y: Double(center.y) - radius, width: radius * 2, height: radius * 2)
			$0.cornerRadius = radius
			$0.font = NSFont.systemFont(ofSize: CGFloat(radius * 2 / 3))
		}
	}

	override open var wantsUpdateLayer: Bool {
		return true
	}

	@IBInspectable override open var title: String {
		didSet {
			setTitle()
		}
	}

	@IBInspectable public var textColor: NSColor = .white {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var activeTextColor: NSColor = .white {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var cornerRadius: Double = 4 {
		didSet {
			needsDisplay = true
		}
	}

	@IBInspectable public var borderWidth: Double = 0 {
		didSet {
			needsDisplay = true
		}
	}

	@IBInspectable public var borderColor: NSColor = .controlAccentColorPolyfill {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var activeBorderColor: NSColor = .controlAccentColorPolyfill {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var backgroundColor: NSColor = .controlAccentColorPolyfill {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var activeBackgroundColor: NSColor = .controlAccentColorPolyfill {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var shadowRadius: Double = 0 {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var activeShadowRadius: Double = -1 {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var shadowOpacity: Double = 0 {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var activeShadowOpacity: Double = -1 {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var shadowColor: NSColor = .controlShadowColor {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	@IBInspectable public var activeShadowColor: NSColor? {
		didSet {
			needsDisplay = true
			animateColor()
		}
	}

	override open var font: NSFont? {
		didSet {
			setTitle()
		}
	}

	override open var isEnabled: Bool {
		didSet {
			alphaValue = isEnabled ? 1 : 0.6
		}
	}

	public convenience init() {
		self.init(frame: .zero)
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
		setup()
	}

	override init(frame: CGRect) {
		super.init(frame: frame)
		setup()
	}

	// Ensure the button doesn't draw its default contents
	override open func draw(_ dirtyRect: CGRect) {}
	override open func drawFocusRingMask() {}

	override open func layout() {
		super.layout()
		positionTitle()
	}

	override open func viewDidChangeBackingProperties() {
		super.viewDidChangeBackingProperties()

		if let scale = window?.backingScaleFactor {
			layer?.contentsScale = scale
			titleLayer.contentsScale = scale
		}
	}

	private func setup() {
		wantsLayer = true

		layer?.masksToBounds = false

		titleLayer.alignmentMode = .center
		titleLayer.contentsScale = window?.backingScaleFactor ?? 2
		layer?.addSublayer(titleLayer)
		setTitle()

		needsDisplay = true
	}

	public typealias ColorGenerator = () -> NSColor

	private var colorGenerators = [KeyPath<CustomButton, NSColor>: ColorGenerator]()

	/// Gets or sets the color generation closure for the provided key path.
	///
	/// - Parameter keyPath: The key path that specifies the color related property.
	subscript(colorGenerator keyPath: KeyPath<CustomButton, NSColor>) -> ColorGenerator? {
		get {
			return colorGenerators[keyPath]
		}
		set {
			colorGenerators[keyPath] = newValue
		}
	}

	private func color(for keyPath: KeyPath<CustomButton, NSColor>) -> NSColor {
		return colorGenerators[keyPath]?() ?? self[keyPath: keyPath]
	}

	override open func updateLayer() {
		let isOn = state == .on
		layer?.cornerRadius = CGFloat(cornerRadius)
		layer?.borderWidth = CGFloat(borderWidth)
		layer?.shadowRadius = CGFloat(isOn && activeShadowRadius != -1 ? activeShadowRadius : shadowRadius)
		layer?.shadowOpacity = Float(isOn && activeShadowOpacity != -1 ? activeShadowOpacity : shadowOpacity)
		animateColor()
	}

	private func setTitle() {
		titleLayer.string = title

		if let font = font {
			titleLayer.font = font
			titleLayer.fontSize = font.pointSize
		}

		needsLayout = true
	}

	private func positionTitle() {
		let titleSize = title.size(withAttributes: [.font: font as Any])
		titleLayer.frame = titleSize.centered(in: bounds).roundedOrigin()
	}

	private func animateColor() {
		let isOn = state == .on
		let duration = isOn ? 0.2 : 0.1
		let backgroundColor = isOn ? color(for: \.activeBackgroundColor) : color(for: \.backgroundColor)
		let textColor = isOn ? color(for: \.activeTextColor) : color(for: \.textColor)
		let borderColor = isOn ? color(for: \.activeBorderColor) : color(for: \.borderColor)
		let shadowColor = isOn ? (activeShadowColor ?? color(for: \.shadowColor)) : color(for: \.shadowColor)

		layer?.animate(color: backgroundColor.cgColor, keyPath: #keyPath(CALayer.backgroundColor), duration: duration)
		layer?.animate(color: borderColor.cgColor, keyPath: #keyPath(CALayer.borderColor), duration: duration)
		layer?.animate(color: shadowColor.cgColor, keyPath: #keyPath(CALayer.shadowColor), duration: duration)
		titleLayer.animate(color: textColor.cgColor, keyPath: #keyPath(CATextLayer.foregroundColor), duration: duration)
	}

	private func toggleState() {
		state = state == .off ? .on : .off
		animateColor()
	}

	override open func hitTest(_ point: CGPoint) -> NSView? {
		return isEnabled ? super.hitTest(point) : nil
	}

	override open func mouseDown(with event: NSEvent) {
		isMouseDown = true
		toggleState()
	}

	override open func mouseEntered(with event: NSEvent) {
		if isMouseDown {
			toggleState()
		}
	}

	override open func mouseExited(with event: NSEvent) {
		if isMouseDown {
			toggleState()
			isMouseDown = false
		}
	}

	override open func mouseUp(with event: NSEvent) {
		if isMouseDown {
			isMouseDown = false
			toggleState()
			_ = target?.perform(action, with: self)
		}
	}
}

extension CustomButton: NSViewLayerContentScaleDelegate {
	public func layer(_ layer: CALayer, shouldInheritContentsScale newScale: CGFloat, from window: NSWindow) -> Bool {
		return true
	}
}
