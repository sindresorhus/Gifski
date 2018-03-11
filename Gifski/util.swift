import Cocoa
import AVFoundation


let defaults = UserDefaults.standard


/**
Convenience function for initializing an object and modifying its properties

```
let label = with(NSTextField()) {
	$0.stringValue = "Foo"
	$0.textColor = .systemBlue
	view.addSubview($0)
}
```
*/
@discardableResult
func with<T>(_ item: T, update: (inout T) throws -> Void) rethrows -> T {
	var this = item
	try update(&this)
	return this
}


struct Meta {
	static func openSubmitFeedbackPage() {
		let body =
		"""
		<!-- Provide your feedback here. Include as many details as possible. -->


		---
		\(App.name) \(App.version) (\(App.build))
		macOS \(System.osVersion)
		\(System.hardwareModel)
		"""

		let query: [String: String] = [
			"body": body
		]

		URL(string: "https://github.com/sindresorhus/gifski-app/issues/new")!.addingDictionaryAsQuery(query).open()
	}
}


/// This is useful as `awakeFromNib` is not called for programatically created views
class SSView: NSView {
	var didAppearWasCalled = false

	/// Meant to be overridden in subclasses
	func didAppear() {}

	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()

		if !didAppearWasCalled {
			didAppearWasCalled = true
			didAppear()
		}
	}
}


extension NSWindow {
	var toolbarView: NSView? {
		return standardWindowButton(.closeButton)?.superview
	}

	var titlebarView: NSView? {
		return toolbarView?.superview
	}

	var titlebarHeight: Double {
		return Double(titlebarView?.bounds.height ?? 0)
	}
}


extension NSWindowController: NSWindowDelegate {
	public func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: CGRect) -> CGRect {
		// Adjust sheet position so it goes below the traffic lights
		if window.styleMask.contains(.fullSizeContentView) {
			return rect.offsetBy(dx: 0, dy: CGFloat(-window.titlebarHeight))
		}

		return rect
	}
}


extension NSAppearance {
	static let aqua = NSAppearance(named: .aqua)!
	static let light = NSAppearance(named: .vibrantLight)!
	static let dark = NSAppearance(named: .vibrantDark)!

	static var system: NSAppearance {
		let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
		return NSAppearance(named: isDark ? .vibrantDark : .vibrantLight)!
	}
}


extension NSAppearance {
	private struct AssociatedKeys {
		static let app = AssociatedObject<NSAppearance>()
	}

	/// The chosen appearance for the app
	/// We're not using `.current` as it doesn't work across threads
	static var app: NSAppearance {
		get {
			return AssociatedKeys.app[self] ?? .aqua
		}
		set {
			current = newValue
			AssociatedKeys.app[self] = newValue
		}
	}
}


extension NSColor {
	/// Get the complementary color of the current color
	var complementary: NSColor {
		guard let ciColor = CIColor(color: self) else {
			return self
		}

		let compRed = 1 - ciColor.red
		let compGreen = 1 - ciColor.green
		let compBlue = 1 - ciColor.blue

		return NSColor(red: compRed, green: compGreen, blue: compBlue, alpha: alphaComponent)
	}
}


extension NSView {
	/**
	Iterate through subviews of a specific type and change properties on them

	```
	view.forEachSubview(ofType: NSTextField.self) {
		$0.textColor = .white
	}
	```
	*/
	func forEachSubview<T>(ofType type: T.Type, deep: Bool = true, closure: (T) -> Void) {
		for view in subviews {
			if let view = view as? T {
				closure(view)
			} else if deep {
				view.forEachSubview(ofType: type, deep: deep, closure: closure)
			}
		}
	}

	func invertTextColorOnTextFieldsIfDark() {
		guard NSAppearance.app == .dark else {
			return
		}

		forEachSubview(ofType: NSTextField.self) {
			$0.textColor = $0.textColor?.complementary
		}
	}
}


extension NSAlert {
	/// Show a modal alert sheet on a window
	/// If the window is nil, it will be a app-modal alert
	static func showModal(
		for window: NSWindow?,
		title: String,
		message: String? = nil,
		style: NSAlert.Style = .critical
	) -> NSApplication.ModalResponse {
		guard let window = window else {
			return NSAlert(
				title: title,
				message: message,
				style: style
			).runModal()
		}

		return NSAlert(
			title: title,
			message: message,
			style: style
		).runModal(for: window)
	}

	/// Show a app-modal (window indepedendent) alert
	static func showModal(
		title: String,
		message: String? = nil,
		style: NSAlert.Style = .critical
	) -> NSApplication.ModalResponse {
		return NSAlert(
			title: title,
			message: message,
			style: style
		).runModal()
	}

	convenience init(
		title: String,
		message: String? = nil,
		style: NSAlert.Style = .critical
	) {
		self.init()
		self.messageText = title
		self.alertStyle = style

		if let message = message {
			self.informativeText = message
		}

		// Adhere to the current app appearance
		self.appearance = .app
	}

	var appearance: NSAppearance {
		get {
			return window.appearance ?? .aqua
		}
		set {
			window.appearance = newValue
		}
	}

	/// Runs the alert as a window-modal sheel
	func runModal(for window: NSWindow) -> NSApplication.ModalResponse {
		beginSheetModal(for: window) { returnCode in
			NSApp.stopModal(withCode: returnCode)
		}

		return NSApp.runModal(for: window)
	}
}


extension NSView {
	func copyView<T: NSView>() -> T {
		return NSKeyedUnarchiver.unarchiveObject(with: NSKeyedArchiver.archivedData(withRootObject: self)) as! T
	}

	/**
	Animate by placing a copy of the view above it, changing properties on the view, and then fading out the copy.
	Can be useful for properties that cannot normally be animated.
	*/
	func animateCrossFade(
		duration: TimeInterval = 1,
		delay: TimeInterval = 0,
		animations: @escaping (() -> Void),
		completion: (() -> Void)? = nil
	) {
		let fadeView = copyView()
		superview?.addSubview(fadeView, positioned: .above, relativeTo: nil)
		animations()
		fadeView.fadeOut(duration: duration, delay: delay, completion: completion)
	}
}


extension NSTextField {
	/**
	Animate the text color.
	We cannot use `NSView.animate()` here as the property is not animatable.
	*/
	func animateTextColor(
		to color: NSColor,
		duration: TimeInterval = 0.5,
		delay: TimeInterval = 0,
		completion: (() -> Void)? = nil
	) {
		animateCrossFade(duration: duration, delay: delay, animations: {
			self.textColor = color
		}, completion: completion)
	}
}


extension NSBezierPath {
	/// UIKit polyfill
	var cgPath: CGPath {
		let path = CGMutablePath()
		var points = [CGPoint](repeating: .zero, count: 3)

		for i in 0..<elementCount {
			let type = element(at: i, associatedPoints: &points)
			switch type {
			case .moveToBezierPathElement:
				path.move(to: points[0])
			case .lineToBezierPathElement:
				path.addLine(to: points[0])
			case .curveToBezierPathElement:
				path.addCurve(to: points[2], control1: points[0], control2: points[1])
			case .closePathBezierPathElement:
				path.closeSubpath()
			}
		}

		return path
	}

	/// UIKit polyfill
	convenience init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
		self.init(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
	}
}


extension AVAssetImageGenerator {
	func generateCGImagesAsynchronously(forTimePoints timePoints: [CMTime], completionHandler: @escaping AVAssetImageGeneratorCompletionHandler) {
		let times = timePoints.map { NSValue(time: $0) }
		generateCGImagesAsynchronously(forTimes: times, completionHandler: completionHandler)
	}
}


extension CMTime {
	static var zero: CMTime = kCMTimeZero
	static var invalid: CMTime = kCMTimeInvalid
}


extension CMTimeScale {
	/**
	```
	CMTime(seconds: (1 / fps) * Double(i), preferredTimescale: .video)
	```
	*/
	static var video: Int32 = 600 // This is what Apple recommends
}


extension Comparable {
	/// Note: It's not possible to implement `Range` or `PartialRangeUpTo` here as we can't know what `1.1..<1.53` would be. They only work with Stridable in our case.

	/// Example: 20.5.clamped(from: 10.3, to: 15)
	func clamped(from lowerBound: Self, to upperBound: Self) -> Self {
		return min(max(self, lowerBound), upperBound)
	}

	/// Example: 20.5.clamped(to: 10.3...15)
	func clamped(to range: ClosedRange<Self>) -> Self {
		return clamped(from: range.lowerBound, to: range.upperBound)
	}

	/// Example: 20.5.clamped(to: ...10.3)
	/// => 10.3
	func clamped(to range: PartialRangeThrough<Self>) -> Self {
		return min(self, range.upperBound)
	}

	/// Example: 5.5.clamped(to: 10.3...)
	/// => 10.3
	func clamped(to range: PartialRangeFrom<Self>) -> Self {
		return max(self, range.lowerBound)
	}
}

extension Strideable where Stride: SignedInteger {
	/// Example: 20.clamped(to: 5..<10)
	/// => 9
	func clamped(to range: CountableRange<Self>) -> Self {
		return clamped(from: range.lowerBound, to: range.upperBound.advanced(by: -1))
	}

	/// Example: 20.clamped(to: 5...10)
	/// => 10
	func clamped(to range: CountableClosedRange<Self>) -> Self {
		return clamped(from: range.lowerBound, to: range.upperBound)
	}

	/// Example: 20.clamped(to: ..<10)
	/// => 9
	func clamped(to range: PartialRangeUpTo<Self>) -> Self {
		return min(self, range.upperBound.advanced(by: -1))
	}
}


extension NSViewController {
	var appDelegate: AppDelegate {
		return NSApp.delegate as! AppDelegate
	}
}


extension AVAsset {
	var isVideoDecodable: Bool {
		guard isReadable,
			let firstVideoTrack = tracks(withMediaType: .video).first else {
				return false
			}

		return firstVideoTrack.isDecodable
	}

	var isAudioDecodable: Bool {
		guard isReadable,
			let firstAudioTrack = tracks(withMediaType: .audio).first else {
				return false
			}

		return firstAudioTrack.isDecodable
	}
}
/// Video metadata
extension AVURLAsset {
	struct VideoMetadata {
		let dimensions: CGSize
		let duration: Double
		let frameRate: Double
		let fileSize: Int
	}

	var videoMetadata: VideoMetadata? {
		guard let track = tracks(withMediaType: .video).first else {
			return nil
		}

		let dimensions = track.naturalSize.applying(track.preferredTransform)

		return VideoMetadata(
			dimensions: CGSize(width: fabs(dimensions.width), height: fabs(dimensions.height)),
			duration: duration.seconds,
			frameRate: Double(track.nominalFrameRate),
			fileSize: url.fileSize
		)
	}
}
extension URL {
	var videoMetadata: AVURLAsset.VideoMetadata? {
		return AVURLAsset(url: self).videoMetadata
	}

	var isVideoDecodable: Bool {
		return AVAsset(url: self).isVideoDecodable
	}

	var isAudioDecodable: Bool {
		return AVAsset(url: self).isAudioDecodable
	}
}


extension CALayer {
	/**
	Set CALayer properties without the implicit animation

	```
	CALayer.withoutImplicitAnimations {
		view.layer?.opacity = 0.4
	}
	```
	*/
	static func withoutImplicitAnimations(closure: () -> Void) {
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		closure()
		CATransaction.commit()
	}

	/**
	Set CALayer properties with the implicit animation
	This is the default, but instances might have manually turned it off

	```
	CALayer.withImplicitAnimations {
		view.layer?.opacity = 0.4
	}
	```
	*/
	static func withImplicitAnimations(closure: () -> Void) {
		CATransaction.begin()
		CATransaction.setDisableActions(false)
		closure()
		CATransaction.commit()
	}

	/**
	Toggle the implicit CALayer animation
	Can be useful for text layers
	*/
	var implicitAnimations: Bool {
		get {
			return actions == nil
		}
		set {
			if newValue {
				actions = nil
			} else {
				actions = ["contents": NSNull()]
			}
		}
	}
}

extension CALayer {
	/// This is required for CALayers that are created independently of a view
	func setAutomaticContentsScale() {
		/// TODO: This should ideally use the screen the layer is currently on. I think we need to first find the window the layer is positioned and then the screen from that.
		contentsScale = NSScreen.main?.backingScaleFactor ?? 2
	}
}


extension NSView {
	func center(inView view: NSView) {
		translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			centerXAnchor.constraint(equalTo: view.centerXAnchor),
			centerYAnchor.constraint(equalTo: view.centerYAnchor)
		])
	}

	func addSubviewToCenter(_ view: NSView) {
		addSubview(view)
		view.center(inView: superview!)
	}
}


extension NSControl {
	/// Trigger the `.action` selector on the control
	func triggerAction() {
		sendAction(action, to: target)
	}
}


extension DispatchQueue {
	/**
	```
	DispatchQueue.main.asyncAfter(duration: 100.milliseconds) {
		print("100 ms later")
	}
	```
	*/
	func asyncAfter(duration: TimeInterval, execute: @escaping () -> Void) {
		asyncAfter(deadline: .now() + duration, execute: execute)
	}
}


/**
```
let foo = Label(text: "Foo")
```
*/
final class Label: NSTextField {
	var text: String {
		get {
			return stringValue
		}
		set {
			stringValue = newValue
		}
	}

	/// Allow the it to be disabled like other NSControl's
	override var isEnabled: Bool {
		didSet {
			textColor = isEnabled ? .controlTextColor : .disabledControlTextColor
		}
	}

	/// Support setting the text later with the `.text` property
	convenience init() {
		self.init(labelWithString: "")
	}

	convenience init(text: String) {
		self.init(labelWithString: text)
	}

	convenience init(attributedText: NSAttributedString) {
		self.init(labelWithAttributedString: attributedText)
	}
}


extension NSView {
	/// UIKit polyfill
	var center: CGPoint {
		get {
			return frame.center
		}
		set {
			frame.center = newValue
		}
	}

	func centerInRect(_ rect: CGRect) {
		center = CGPoint(x: rect.midX, y: rect.midY)
	}

	/// Passing in a window can be useful when the view is not yet added to a window
	/// If you don't pass in a window, it will use the window the view is in
	func centerInWindow(_ window: NSWindow? = nil) {
		guard let view = (window ?? self.window)?.contentView else {
			return
		}

		centerInRect(view.bounds)
	}
}


/**
Mark unimplemented functions and have them fail with a useful message

```
func foo() {
	unimplemented()
}

foo()
//=> "foo() in main.swift:1 has not been implemented"
```
*/
func unimplemented(function: StaticString = #function, file: String = #file, line: UInt = #line) -> Never {
	fatalError("\(function) in \(file.nsString.lastPathComponent):\(line) has not been implemented")
}


extension NSDraggingInfo {
	/// Get the file URLs from dragged and dropped files
	func fileURLs(types: [String] = ["public.item"]) -> [URL] {
		guard draggingPasteboard().types?.contains(.fileURL) == true else {
			return []
		}

		if let urls = draggingPasteboard().readObjects(
			forClasses: [NSURL.self],
			options: [
				.urlReadingFileURLsOnly: true,
				.urlReadingContentsConformToTypes: types
			]
			) as? [URL] {
			return urls
		}

		return []
	}
}


/// Subclass this in Interface Builder with the title "Send Feedback…"
final class FeedbackMenuItem: NSMenuItem {
	required init(coder decoder: NSCoder) {
		super.init(coder: decoder)
		onAction = { _ in
			Meta.openSubmitFeedbackPage()
		}
	}
}


/// Subclass this in Interface Builder and set the `Url` field there
final class UrlMenuItem: NSMenuItem {
	@IBInspectable var url: String?

	required init(coder decoder: NSCoder) {
		super.init(coder: decoder)
		onAction = { _ in
			NSWorkspace.shared.open(URL(string: self.url!)!)
		}
	}
}


final class AssociatedObject<T: Any> {
	subscript(index: Any) -> T? {
		get {
			return objc_getAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque()) as! T?
		} set {
			objc_setAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque(), newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}
	}
}


/// Identical to above, but for NSMenuItem
extension NSMenuItem {
	typealias ActionClosure = ((NSMenuItem) -> Void)

	private struct AssociatedKeys {
		static let onActionClosure = AssociatedObject<ActionClosure>()
	}

	@objc
	private func callClosure(_ sender: NSMenuItem) {
		onAction?(sender)
	}

	/**
	Closure version of `.action`

	```
	let menuItem = NSMenuItem(title: "Unicorn")

	menuItem.onAction = { sender in
		print("NSMenuItem action: \(sender)")
	}
	```
	*/
	var onAction: ActionClosure? {
		get {
			return AssociatedKeys.onActionClosure[self]
		}
		set {
			AssociatedKeys.onActionClosure[self] = newValue
			action = #selector(callClosure)
			target = self
		}
	}
}


extension UserDefaults {
	@nonobjc subscript(key: String) -> Any? {
		get {
			return object(forKey: key)
		}
		set {
			set(newValue, forKey: key)
		}
	}
}


extension NSControl {
	typealias ActionClosure = ((NSControl) -> Void)

	private struct AssociatedKeys {
		static let onActionClosure = AssociatedObject<ActionClosure>()
	}

	@objc
	private func callClosure(_ sender: NSControl) {
		onAction?(sender)
	}

	/**
	Closure version of `.action`

	```
	let button = NSButton(title: "Unicorn", target: nil, action: nil)

	button.onAction = { sender in
		print("Button action: \(sender)")
	}
	```
	*/
	var onAction: ActionClosure? {
		get {
			return AssociatedKeys.onActionClosure[self]
		}
		set {
			AssociatedKeys.onActionClosure[self] = newValue
			action = #selector(callClosure)
			target = self
		}
	}
}


extension CAMediaTimingFunction {
	static let `default` = CAMediaTimingFunction(name: kCAMediaTimingFunctionDefault)
	static let linear = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
	static let easeIn = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
	static let easeOut = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
	static let easeInOut = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
}


extension NSView {
	/**
	```
	let label = NSTextField(labelWithString: "Unicorn")
	view.addSubviewByFadingIn(label)
	```
	*/
	func addSubviewByFadingIn(_ view: NSView, duration: TimeInterval = 1, completion: (() -> Void)? = nil) {
		NSAnimationContext.runAnimationGroup({ context in
			context.duration = duration
			animator().addSubview(view)
		}, completionHandler: completion)
	}

	func removeSubviewByFadingOut(_ view: NSView, duration: TimeInterval = 1, completion: (() -> Void)? = nil) {
		NSAnimationContext.runAnimationGroup({ context in
			context.duration = duration
			view.animator().removeFromSuperview()
		}, completionHandler: completion)
	}

	static func animate(
		duration: TimeInterval = 1,
		delay: TimeInterval = 0,
		timingFunction: CAMediaTimingFunction = .easeInOut,
		animations: @escaping (() -> Void),
		completion: (() -> Void)? = nil
	) {
		DispatchQueue.main.asyncAfter(duration: delay) {
			NSAnimationContext.runAnimationGroup({ context in
				context.allowsImplicitAnimation = true
				context.duration = duration
				context.timingFunction = timingFunction
				animations()
			}, completionHandler: completion)
		}
	}

	func fadeIn(duration: TimeInterval = 1, delay: TimeInterval = 0, completion: (() -> Void)? = nil) {
		isHidden = true

		NSView.animate(duration: duration, delay: delay, animations: {
			self.isHidden = false
		}, completion: completion)
	}

	func fadeOut(duration: TimeInterval = 1, delay: TimeInterval = 0, completion: (() -> Void)? = nil) {
		isHidden = false

		NSView.animate(duration: duration, delay: delay, animations: {
			self.alphaValue = 0
		}, completion: {
			self.isHidden = true
			self.alphaValue = 1
			completion?()
		})
	}
}


extension String {
	// NSString has some useful properties that String does not
	var nsString: NSString {
		return self as NSString
	}
}


struct App {
	static let id = Bundle.main.bundleIdentifier!
	static let name = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
	static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
	static let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
}


/// Convenience for opening URLs
extension URL {
	func open() {
		NSWorkspace.shared.open(self)
	}
}
extension String {
	/*
	```
	"https://sindresorhus.com".openUrl()
	```
	*/
	func openUrl() {
		URL(string: self)?.open()
	}
}


struct System {
	static let osVersion: String = {
		let os = ProcessInfo.processInfo.operatingSystemVersion
		return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
	}()

	static let hardwareModel: String = {
		var size = 0
		sysctlbyname("hw.model", nil, &size, nil, 0)
		var model = [CChar](repeating: 0, count: size)
		sysctlbyname("hw.model", &model, &size, nil, 0)
		return String(cString: model)
	}()

	static let supportedVideoTypes = [
		AVFileType.mp4.rawValue,
		AVFileType.m4v.rawValue,
		AVFileType.mov.rawValue
	]
}


private func escapeQuery(_ query: String) -> String {
	// From RFC 3986
	let generalDelimiters = ":#[]@"
	let subDelimiters = "!$&'()*+,;="

	var allowedCharacters = CharacterSet.urlQueryAllowed
	allowedCharacters.remove(charactersIn: generalDelimiters + subDelimiters)
	return query.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? query
}


extension Dictionary where Key: ExpressibleByStringLiteral, Value: ExpressibleByStringLiteral {
	var asQueryItems: [URLQueryItem] {
		return map {
			URLQueryItem(
				name: escapeQuery($0 as! String),
				value: escapeQuery($1 as! String)
			)
		}
	}

	var asQueryString: String {
		var components = URLComponents()
		components.queryItems = asQueryItems
		return components.query!
	}
}


extension URLComponents {
	mutating func addDictionaryAsQuery(_ dict: [String: String]) {
		percentEncodedQuery = dict.asQueryString
	}
}


extension URL {
	var directoryURL: URL {
		return deletingLastPathComponent()
	}

	var directory: String {
		return directoryURL.path
	}

	var filename: String {
		get {
			return lastPathComponent
		}
		set {
			deleteLastPathComponent()
			appendPathComponent(newValue)
		}
	}

	var fileExtension: String {
		get {
			return pathExtension
		}
		set {
			deletePathExtension()
			appendPathExtension(newValue)
		}
	}

	var filenameWithoutExtension: String {
		get {
			return deletingPathExtension().lastPathComponent
		}
		set {
			let ext = pathExtension
			deleteLastPathComponent()
			appendPathComponent(newValue)
			appendPathExtension(ext)
		}
	}

	func changingFileExtension(to fileExtension: String) -> URL {
		var url = self
		url.fileExtension = fileExtension
		return url
	}

	func addingDictionaryAsQuery(_ dict: [String: String]) -> URL {
		var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
		components.addDictionaryAsQuery(dict)
		return components.url ?? self
	}

	private func resourceValue<T>(forKey key: URLResourceKey) -> T? {
		guard let values = try? resourceValues(forKeys: [key]) else {
			return nil
		}

		return values.allValues[key] as? T
	}

	/// File UTI
	var typeIdentifier: String? {
		return resourceValue(forKey: .typeIdentifierKey)
	}

	/// File size in bytes
	var fileSize: Int {
		return resourceValue(forKey: .fileSizeKey) ?? 0
	}
}

extension CGSize {
	static func * (lhs: CGSize, rhs: Double) -> CGSize {
		return CGSize(width: lhs.width * CGFloat(rhs), height: lhs.height * CGFloat(rhs))
	}

	init(widthHeight: CGFloat) {
		self.width = widthHeight
		self.height = widthHeight
	}
}

extension CGRect {
	init(origin: CGPoint = .zero, width: CGFloat, height: CGFloat) {
		self.origin = origin
		self.size = CGSize(width: width, height: height)
	}

	init(widthHeight: CGFloat) {
		self.origin = .zero
		self.size = CGSize(widthHeight: widthHeight)
	}

	var x: CGFloat {
		get {
			return origin.x
		}
		set {
			origin.x = newValue
		}
	}

	var y: CGFloat {
		get {
			return origin.y
		}
		set {
			origin.y = newValue
		}
	}

	/// `width` and `height` are defined in Foundation as getters only. We add support for setters too.
	/// These will not work when imported as a framework: https://bugs.swift.org/browse/SR-4017
	var width: CGFloat {
		get {
			return size.width
		}
		set {
			size.width = newValue
		}
	}

	var height: CGFloat {
		get {
			return size.height
		}
		set {
			size.height = newValue
		}
	}

	// MARK: - Edges

	var left: CGFloat {
		get {
			return x
		}
		set {
			x = newValue
		}
	}

	var right: CGFloat {
		get {
			return x + width
		}
		set {
			x = newValue - width
		}
	}

	#if os(macOS)
		var top: CGFloat {
			get {
				return y + height
			}
			set {
				y = newValue - height
			}
		}

		var bottom: CGFloat {
			get {
				return y
			}
			set {
				y = newValue
			}
		}
	#else
		var top: CGFloat {
			get {
				return y
			}
			set {
				y = newValue
			}
		}

		var bottom: CGFloat {
			get {
				return y + height
			}
			set {
				y = newValue - height
			}
		}
	#endif

	// MARK: -

	var center: CGPoint {
		get {
			return CGPoint(x: midX, y: midY)
		}
		set {
			origin = CGPoint(
				x: newValue.x - (size.width / 2),
				y: newValue.y - (size.height / 2)
			)
		}
	}

	var centerX: CGFloat {
		get {
			return midX
		}
		set {
			center = CGPoint(x: newValue, y: midY)
		}
	}

	var centerY: CGFloat {
		get {
			return midY
		}
		set {
			center = CGPoint(x: midX, y: newValue)
		}
	}

	// Returns a rect of `size` centered in this rect
	func centered(size: CGSize) -> CGRect {
		let dx = width - size.width
		let dy = height - size.height
		return CGRect(x: x + dx * 0.5, y: y + dy * 0.5, width: size.width, height: size.height)
	}
}
