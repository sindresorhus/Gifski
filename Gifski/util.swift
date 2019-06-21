import Cocoa
import AVFoundation
import class Quartz.QLPreviewPanel

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
	static func openSubmitFeedbackPage(message: String? = nil) {
		let defaultMessage = "<!--\nProvide your feedback here. Include as many details as possible.\nYou can also email me at sindresorhus@gmail.com\n-->"

		let body =
			"""
			\(message ?? defaultMessage)


			---
			\(App.name) \(App.versionWithBuild)
			macOS \(System.osVersion)
			\(System.hardwareModel)
			"""

		let query: [String: String] = [
			"body": body
		]

		URL(string: "https://github.com/sindresorhus/Gifski/issues/new")!.addingDictionaryAsQuery(query).open()
	}
}


/// macOS 10.14 polyfills
extension NSColor {
	static let controlAccentColorPolyfill: NSColor = {
		if #available(macOS 10.14, *) {
			return NSColor.controlAccentColor
		} else {
			// swiftlint:disable:next object_literal
			return NSColor(red: 0.10, green: 0.47, blue: 0.98, alpha: 1)
		}
	}()
}


extension NSColor {
	func with(alpha: Double) -> NSColor {
		return withAlphaComponent(CGFloat(alpha))
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
	// Helper
	private static func centeredOnScreen(rect: CGRect) -> CGRect {
		guard let screen = NSScreen.main else {
			return rect
		}

		// Looks better than perfectly centered
		let yOffset = 0.12

		return rect.centered(in: screen.visibleFrame, xOffsetPercent: 0, yOffsetPercent: yOffset)
	}

	static let defaultContentSize = CGSize(width: 480, height: 300)

	// TODO: Find a way to stack windows, so additional windows are not placed exactly on top of previous ones: https://github.com/sindresorhus/Gifski/pull/30#discussion_r175337064
	static var defaultContentRect: CGRect {
		return centeredOnScreen(rect: defaultContentSize.cgRect)
	}

	static let defaultStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

	static func centeredWindow(size: CGSize = defaultContentSize) -> Self {
		let window = self.init(
			contentRect: NSWindow.defaultContentRect,
			styleMask: NSWindow.defaultStyleMask,
			backing: .buffered,
			defer: true
		)
		window.setContentSize(size)
		window.centerNatural()
		return window
	}

	@nonobjc
	override convenience init() {
		self.init(contentRect: NSWindow.defaultContentRect)
	}

	convenience init(contentRect: CGRect) {
		self.init(contentRect: contentRect, styleMask: NSWindow.defaultStyleMask, backing: .buffered, defer: true)
	}

	/// Moves the window to the center of the screen, slightly more in the center than `window#center()`
	func centerNatural() {
		setFrame(NSWindow.centeredOnScreen(rect: frame), display: true)
	}
}


extension NSWindowController {
	/// Expose the `view` like in NSViewController
	var view: NSView? {
		return window?.contentView
	}
}


extension NSView {
	@discardableResult
	func insertVibrancyView(
		material: NSVisualEffectView.Material = .appearanceBased,
		blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
		appearanceName: NSAppearance.Name? = nil
	) -> NSVisualEffectView {
		let view = NSVisualEffectView(frame: bounds)
		view.autoresizingMask = [.width, .height]
		view.material = material
		view.blendingMode = blendingMode

		if let appearanceName = appearanceName {
			view.appearance = NSAppearance(named: appearanceName)
		}

		addSubview(view, positioned: .below, relativeTo: nil)

		return view
	}
}


extension NSWindow {
	func makeVibrant() {
		if #available(OSX 10.14, *) {
			contentView?.insertVibrancyView(material: .underWindowBackground)
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




extension NSAlert {
	/// Show an alert as a window-modal sheet, or as an app-modal (window-indepedendent) alert if the window is `nil` or not given.
	@discardableResult
	static func showModal(
		for window: NSWindow? = nil,
		message: String,
		informativeText: String? = nil,
		style: NSAlert.Style = .warning
	) -> NSApplication.ModalResponse {
		return NSAlert(
			message: message,
			informativeText: informativeText,
			style: style
		).runModal(for: window)
	}

	convenience init(
		message: String,
		informativeText: String? = nil,
		style: NSAlert.Style = .warning
	) {
		self.init()
		self.messageText = message
		self.alertStyle = style

		if let informativeText = informativeText {
			self.informativeText = informativeText
		}
	}

	/// Runs the alert as a window-modal sheet, or as an app-modal (window-indepedendent) alert if the window is `nil` or not given.
	@discardableResult
	func runModal(for window: NSWindow? = nil) -> NSApplication.ModalResponse {
		guard let window = window else {
			return runModal()
		}

		beginSheetModal(for: window) { returnCode in
			NSApp.stopModal(withCode: returnCode)
		}

		return NSApp.runModal(for: window)
	}
}


extension AVAssetImageGenerator {
	struct CompletionHandlerResult {
		let image: CGImage
		let requestedTime: CMTime
		let actualTime: CMTime
		let completedCount: Int
		let totalCount: Int
		let isFinished: Bool
	}

	func generateCGImagesAsynchronously(
		forTimePoints timePoints: [CMTime],
		completionHandler: @escaping (Swift.Result<CompletionHandlerResult, Error>) -> Void
	) {
		let times = timePoints.map { NSValue(time: $0) }
		let totalCount = times.count
		var completedCount = 0

		generateCGImagesAsynchronously(forTimes: times) { requestedTime, image, actualTime, result, error in
			switch result {
			case .succeeded:
				completedCount += 1

				completionHandler(
					.success(
						CompletionHandlerResult(
							image: image!,
							requestedTime: requestedTime,
							actualTime: actualTime,
							completedCount: completedCount,
							totalCount: totalCount,
							isFinished: completedCount == totalCount
						)
					)
				)
			case .failed:
				completionHandler(.failure(error!))
			case .cancelled:
				completionHandler(.failure(CancellationError()))
			@unknown default:
				assertionFailure("AVAssetImageGenerator.generateCGImagesAsynchronously() received a new enum case. Please handle it.")
			}
		}
	}
}


extension CMTimeScale {
	/**
	```
	CMTime(seconds: 1 / fps, preferredTimescale: .video)
	```
	*/
	static var video: CMTimeScale = 600 // This is what Apple recommends
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


extension FixedWidthInteger {
	/// Returns the integer formatted as a human readble file size.
	/// Example: `2.3 GB`
	var bytesFormattedAsFileSize: String {
		return ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
	}
}


extension String.StringInterpolation {
	/**
	Interpolate the value by unwrapping it, and if `nil`, use the given default string.

	```
	// This doesn't work as you can only use nil coalescing in interpolation with the same type as the optional
	"foo \(optionalDouble ?? "none")

	// Now you can do this
	"foo \(optionalDouble, default: "none")
	```
	*/
	public mutating func appendInterpolation(_ value: Any?, default defaultValue: String) {
		if let value = value {
			appendInterpolation(value)
		} else {
			appendLiteral(defaultValue)
		}
	}

	/**
	Interpolate the value by unwrapping it, and if `nil`, use `"nil"`.

	```
	// This doesn't work as you can only use nil coalescing in interpolation with the same type as the optional
	"foo \(optionalDouble ?? "nil")

	// Now you can do this
	"foo \(describing: optionalDouble)
	```
	*/
	public mutating func appendInterpolation(describing value: Any?) {
		if let value = value {
			appendInterpolation(value)
		} else {
			appendLiteral("nil")
		}
	}
}


// TODO: Make this a `BinaryFloatingPoint` extension instead
extension Double {
	/**
	Converts the number to a string and strips fractional trailing zeros.

	```
	let x = 1.0

	print(1.0)
	//=> "1.0"

	print(1.0.formatted)
	//=> "1"

	print(0.0100.formatted)
	//=> "0.01"
	```
	*/
	var formatted: String {
	   return truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
	}
}
extension CGFloat {
	var formatted: String {
		return Double(self).formatted
	}
}


extension CGSize {
	/// Example: `140×100`
	var formatted: String {
		return "\(width.formatted)×\(height.formatted)"
	}
}


extension NSImage {
	/// UIImage polyfill
	convenience init(cgImage: CGImage) {
		let size = CGSize(width: cgImage.width, height: cgImage.height)
		self.init(cgImage: cgImage, size: size)
	}
}


extension CGImage {
	var nsImage: NSImage {
		return NSImage(cgImage: self)
	}
}


extension AVAssetImageGenerator {
	func image(at time: CMTime) -> NSImage? {
		return (try? copyCGImage(at: time, actualTime: nil))?.nsImage
	}
}

extension AVAsset {
	func image(at time: CMTime) -> NSImage? {
		let imageGenerator = AVAssetImageGenerator(asset: self)
		imageGenerator.appliesPreferredTrackTransform = true
		imageGenerator.requestedTimeToleranceAfter = .zero
		imageGenerator.requestedTimeToleranceBefore = .zero
		return imageGenerator.image(at: time)
	}
}


extension AVAssetTrack {
	/// Returns the dimensions of the track if it's a video.
	var dimensions: CGSize? {
		guard naturalSize != .zero else {
			return nil
		}

		let size = naturalSize.applying(preferredTransform)
		let preferredSize = CGSize(width: abs(size.width), height: abs(size.height))

		// Workaround for https://github.com/sindresorhus/Gifski/issues/76
		guard preferredSize != .zero else {
			return asset?.image(at: CMTime(seconds: 0, preferredTimescale: .video))?.size
		}

		return preferredSize
	}

	/// Returns the frame rate of the track if it's a video.
	var frameRate: Double? {
		return Double(nominalFrameRate)
	}

	/// Returns the aspect ratio of the track if it's a video.
	var aspectRatio: Double? {
		guard let dimensions = dimensions else {
			return nil
		}

		return Double(dimensions.height / dimensions.width)
	}

	/// Example:
	/// `avc1` (video)
	/// `aac` (audio)
	var codecString: String? {
		let descriptions = formatDescriptions as! [CMFormatDescription]
		return descriptions.map { CMFormatDescriptionGetMediaSubType($0).toString() }.first
	}

	var codec: AVFormat? {
		guard let codecString = codecString else {
			return nil
		}

		return AVFormat(fourCC: codecString)
	}

	/// Returns a debug string with the media format. Example: `vide/avc1`
	var mediaFormat: String {
		let descriptions = formatDescriptions as! [CMFormatDescription]

		var format = [String]()
		for description in descriptions {
			// Get string representation of media type (vide, soun, sbtl, etc.)
			let type = CMFormatDescriptionGetMediaType(description).toString()

			// Get string representation media subtype (avc1, aac, tx3g, etc.)
			let subType = CMFormatDescriptionGetMediaSubType(description).toString()

			format.append("\(type)/\(subType)")
		}

		return format.joined(separator: ",")
	}

	/// Estimated file size of the track in bytes.
	var estimatedFileSize: Int {
		let dataRateInBytes = Double(estimatedDataRate / 8)
		return Int(timeRange.duration.seconds * dataRateInBytes)
	}
}


/*
> FOURCC is short for "four character code" - an identifier for a video codec, compression format, color or pixel format used in media files.
*/
extension FourCharCode {
	/// Create a String representation of a FourCC.
	func toString() -> String {
		let bytes: [CChar] = [
			CChar((self >> 24) & 0xff),
			CChar((self >> 16) & 0xff),
			CChar((self >> 8) & 0xff),
			CChar(self & 0xff),
			0
		]

		return String(cString: bytes).trimmingCharacters(in: .whitespaces)
	}
}


// TODO: Support audio formats too.
enum AVFormat: String {
	case hevc
	case h264
	case appleProResRAWHQ
	case appleProResRAW
	case appleProRes4444XQ
	case appleProRes4444
	case appleProRes422HQ
	case appleProRes422
	case appleProRes422LT
	case appleProRes422Proxy
	case appleAnimation

	init?(fourCC: String) {
		switch fourCC.trimmingCharacters(in: .whitespaces) {
		case "hvc1":
			self = .hevc
		case "avc1":
			self = .h264
		case "aprh": // From https://avpres.net/Glossar/ProResRAW.html
			self = .appleProResRAWHQ
		case "aprn":
			self = .appleProResRAW
		case "ap4x":
			self = .appleProRes4444XQ
		case "ap4h":
			self = .appleProRes4444
		case "apch":
			self = .appleProRes422HQ
		case "apcn":
			self = .appleProRes422
		case "apcs":
			self = .appleProRes422LT
		case "apco":
			self = .appleProRes422Proxy
		case "rle":
			self = .appleAnimation
		default:
			return nil
		}
	}

	init?(fourCC: FourCharCode) {
		self.init(fourCC: fourCC.toString())
	}

	var fourCC: String {
		switch self {
		case .hevc:
			return "hvc1"
		case .h264:
			return "avc1"
		case .appleProResRAWHQ:
			return "aprh"
		case .appleProResRAW:
			return "aprn"
		case .appleProRes4444XQ:
			return "ap4x"
		case .appleProRes4444:
			return "ap4h"
		case .appleProRes422HQ:
			return "apcn"
		case .appleProRes422:
			return "apch"
		case .appleProRes422LT:
			return "apcs"
		case .appleProRes422Proxy:
			return "apco"
		case .appleAnimation:
			return "rle "
		}
	}

	var isAppleProRes: Bool {
		return [
			.appleProResRAWHQ,
			.appleProResRAW,
			.appleProRes4444XQ,
			.appleProRes4444,
			.appleProRes422HQ,
			.appleProRes422,
			.appleProRes422LT,
			.appleProRes422Proxy
		].contains(self)
	}
}

extension AVFormat: CustomStringConvertible {
	var description: String {
		switch self {
		case .hevc:
			return "HEVC"
		case .h264:
			return "H264"
		case .appleProResRAWHQ:
			return "Apple ProRes RAW HQ"
		case .appleProResRAW:
			return "Apple ProRes RAW"
		case .appleProRes4444XQ:
			return "Apple ProRes 4444 XQ"
		case .appleProRes4444:
			return "Apple ProRes 4444"
		case .appleProRes422HQ:
			return "Apple ProRes 422 HQ"
		case .appleProRes422:
			return "Apple ProRes 422"
		case .appleProRes422LT:
			return "Apple ProRes 422 LT"
		case .appleProRes422Proxy:
			return "Apple ProRes 422 Proxy"
		case .appleAnimation:
			return "Apple Animation"
		}
	}
}

extension AVFormat: CustomDebugStringConvertible {
	var debugDescription: String {
		return "\(description) (\(fourCC))"
	}
}


extension AVMediaType: CustomDebugStringConvertible {
	public var debugDescription: String {
		switch self {
		case .audio:
			return "Audio"
		case .closedCaption:
			return "Closed-caption content"
		case .depthData:
			return "Depth data"
		case .metadata:
			return "Metadata"
		// iOS
		// case .metadataObject:
		// return "Metadata objects"
		case .muxed:
			return "Muxed media"
		case .subtitle:
			return "Subtitles"
		case .text:
			return "Text"
		case .timecode:
			return "Time code"
		case .video:
			return "Video"
		default:
			return "Unknown"
		}
	}
}


extension AVAsset {
	/// Whether the first video track is decodable.
	var isVideoDecodable: Bool {
		guard
			isReadable,
			let firstVideoTrack = tracks(withMediaType: .video).first
		else {
			return false
		}

		return firstVideoTrack.isDecodable
	}

	/// Returns a boolean of whether there are any video tracks.
	var hasVideo: Bool {
		return !tracks(withMediaType: .video).isEmpty
	}

	/// Returns a boolean of whether there are any audio tracks.
	var hasAudio: Bool {
		return !tracks(withMediaType: .audio).isEmpty
	}

	/// Returns the first video track if any.
	var firstVideoTrack: AVAssetTrack? {
		return tracks(withMediaType: .video).first
	}

	/// Returns the first audio track if any.
	var firstAudioTrack: AVAssetTrack? {
		return tracks(withMediaType: .audio).first
	}

	/// Returns the dimensions of the first video track if any.
	var dimensions: CGSize? {
		return firstVideoTrack?.dimensions
	}

	/// Returns the frame rate of the first video track if any.
	var frameRate: Double? {
		return firstVideoTrack?.frameRate
	}

	/// Returns the aspect ratio of the first video track if any.
	var aspectRatio: Double? {
		return firstVideoTrack?.aspectRatio
	}

	/// Returns the video codec of the first video track if any.
	var videoCodec: AVFormat? {
		return firstVideoTrack?.codec
	}

	/// Returns the audio codec of the first audio track if any.
	/// Example: `aac`
	var audioCodec: String? {
		return firstAudioTrack?.codecString
	}

	/// The file size of the asset in bytes.
	/// - Note: If self is an `AVAsset` and not an `AVURLAsset`, the file size will just be an estimate.
	var fileSize: Int {
		guard let urlAsset = self as? AVURLAsset else {
			return tracks.sum { $0.estimatedFileSize }
		}

		return urlAsset.url.fileSize
	}

	var fileSizeFormatted: String {
		return fileSize.bytesFormattedAsFileSize
	}
}

extension AVAsset {
	/// Returns debug info for the asset to use in logging and error messages.
	var debugInfo: String {
		var output = [String]()

		let durationFormatter = DateComponentsFormatter()
		durationFormatter.unitsStyle = .abbreviated

		output.append(
			"""
			## AVAsset debug info ##
			Extension: \(describing: (self as? AVURLAsset)?.url.fileExtension)
			Video codec: \(describing: videoCodec?.debugDescription)
			Audio codec: \(describing: audioCodec)
			Duration: \(describing: durationFormatter.string(from: duration.seconds))
			Dimension: \(describing: dimensions?.formatted)
			Frame rate: \(describing: frameRate?.rounded(toDecimalPlaces: 2).formatted)
			File size: \(fileSizeFormatted)
			Is readable: \(isReadable)
			Is playable: \(isPlayable)
			Is exportable: \(isExportable)
			Has protected content: \(hasProtectedContent)
			"""
		)

		for track in tracks {
			output.append(
				"""
				Track #\(track.trackID)
				----
				Type: \(track.mediaType.debugDescription)
				Codec: \(describing: track.mediaType == .video ? track.codec?.debugDescription : track.codecString)
				Duration: \(describing: durationFormatter.string(from: track.timeRange.duration.seconds))
				Dimensions: \(describing: track.dimensions?.formatted)
				Natural size: \(describing: track.naturalSize)
				Frame rate: \(describing: track.frameRate?.rounded(toDecimalPlaces: 2).formatted)
				Is playable: \(track.isPlayable)
				Is decodable: \(track.isDecodable)
				----
				"""
			)
		}

		return output.joined(separator: "\n\n")
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
		guard
			let dimensions = dimensions,
			let frameRate = frameRate
		else {
			return nil
		}

		return VideoMetadata(
			dimensions: dimensions,
			duration: duration.seconds,
			frameRate: frameRate,
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


extension NSFont {
	var size: CGFloat {
		return fontDescriptor.object(forKey: .size) as! CGFloat
	}

	var traits: [NSFontDescriptor.TraitKey: AnyObject] {
		return fontDescriptor.object(forKey: .traits) as! [NSFontDescriptor.TraitKey: AnyObject]
	}

	var weight: NSFont.Weight {
		return NSFont.Weight(traits[.weight] as! CGFloat)
	}
}


/**
```
let foo = Label(text: "Foo")
```
*/
class Label: NSTextField {
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

	override func viewDidMoveToSuperview() {
		guard superview != nil else {
			return
		}

		sizeToFit()
	}
}

/// Use it in Interface Builder as a class or programmatically
final class MonospacedLabel: Label {
	override init(frame: CGRect) {
		super.init(frame: frame)
		setup()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setup()
	}

	private func setup() {
		if let font = self.font {
			self.font = NSFont.monospacedDigitSystemFont(ofSize: font.size, weight: font.weight)
		}
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
// swiftlint:disable:next unavailable_function
func unimplemented(function: StaticString = #function, file: String = #file, line: UInt = #line) -> Never {
	fatalError("\(function) in \(file.nsString.lastPathComponent):\(line) has not been implemented")
}


extension NSPasteboard {
	/// Get the file URLs from dragged and dropped files
	func fileURLs(types: [String] = []) -> [URL] {
		var options: [NSPasteboard.ReadingOptionKey: Any] = [
			.urlReadingFileURLsOnly: true
		]

		if !types.isEmpty {
			options[.urlReadingContentsConformToTypes] = types
		}

		guard let urls = readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
			return []
		}

		return urls
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
	static let `default` = CAMediaTimingFunction(name: .default)
	static let linear = CAMediaTimingFunction(name: .linear)
	static let easeIn = CAMediaTimingFunction(name: .easeIn)
	static let easeOut = CAMediaTimingFunction(name: .easeOut)
	static let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
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
		timingFunction: CAMediaTimingFunction = .default,
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

		NSView.animate(
			duration: duration,
			delay: delay,
			animations: {
				self.isHidden = false
			},
			completion: completion
		)
	}

	func fadeOut(duration: TimeInterval = 1, delay: TimeInterval = 0, completion: (() -> Void)? = nil) {
		isHidden = false

		NSView.animate(
			duration: duration,
			delay: delay,
			animations: {
				self.alphaValue = 0
			},
			completion: {
				self.isHidden = true
				self.alphaValue = 1
				completion?()
			}
		)
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
	static let versionWithBuild = "\(version) (\(build))"
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

	private func boolResourceValue(forKey key: URLResourceKey, defaultValue: Bool = false) -> Bool {
		guard let values = try? resourceValues(forKeys: [key]) else {
			return defaultValue
		}

		return values.allValues[key] as? Bool ?? defaultValue
	}

	/// File UTI
	var typeIdentifier: String? {
		return resourceValue(forKey: .typeIdentifierKey)
	}

	/// File size in bytes
	var fileSize: Int {
		return resourceValue(forKey: .fileSizeKey) ?? 0
	}

	var fileSizeFormatted: String {
		return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
	}

	var exists: Bool {
		return FileManager.default.fileExists(atPath: path)
	}

	var isReadable: Bool {
		return boolResourceValue(forKey: .isReadableKey)
	}
}

extension URL {
	/**
	Check if the file conforms to the given type identifier

	```
	URL(fileURLWithPath: "video.mp4").conformsTo(typeIdentifier: "public.movie")
	//=> true
	```
	*/
	func conformsTo(typeIdentifier parentTypeIdentifier: String) -> Bool {
		guard let typeIdentifier = typeIdentifier else {
			return false
		}

		return UTTypeConformsTo(typeIdentifier as CFString, parentTypeIdentifier as CFString)
	}

	/// - Important: This doesn't guarantee it's a video. A video container could contain only an audio track. Use the `AVAsset` properties to ensure it's something you can use.
	var isVideo: Bool {
		return conformsTo(typeIdentifier: kUTTypeMovie as String)
	}
}

extension CGSize {
	static func * (lhs: CGSize, rhs: Double) -> CGSize {
		return CGSize(width: lhs.width * CGFloat(rhs), height: lhs.height * CGFloat(rhs))
	}

	static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
		return CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
	}

	init(widthHeight: CGFloat) {
		self.init(width: widthHeight, height: widthHeight)
	}

	var cgRect: CGRect {
		return CGRect(origin: .zero, size: self)
	}

	func aspectFit(to boundingSize: CGSize) -> CGSize {
		let ratio = min(boundingSize.width / width, boundingSize.height / height)
		return self * ratio
	}

	func aspectFit(to widthHeight: CGFloat) -> CGSize {
		return aspectFit(to: CGSize(width: widthHeight, height: widthHeight))
	}
}

extension CGRect {
	init(origin: CGPoint = .zero, width: CGFloat, height: CGFloat) {
		self.init(origin: origin, size: CGSize(width: width, height: height))
	}

	init(widthHeight: CGFloat) {
		self.init()
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

	/**
	Returns a CGRect where `self` is centered in `rect`
	*/
	func centered(in rect: CGRect, xOffset: Double = 0, yOffset: Double = 0) -> CGRect {
		return CGRect(
			x: ((rect.width - size.width) / 2) + CGFloat(xOffset),
			y: ((rect.height - size.height) / 2) + CGFloat(yOffset),
			width: size.width,
			height: size.height
		)
	}

	/**
	Returns a CGRect where `self` is centered in `rect`

	- Parameters:
		- xOffsetPercent: The offset in percentage of `rect.width`
	*/
	func centered(in rect: CGRect, xOffsetPercent: Double, yOffsetPercent: Double) -> CGRect {
		return centered(
			in: rect,
			xOffset: Double(rect.width) * xOffsetPercent,
			yOffset: Double(rect.height) * yOffsetPercent
		)
	}
}

public protocol CancellableError: Error {
	/// Returns true if this Error represents a cancelled condition
	var isCancelled: Bool { get }
}

public struct CancellationError: CancellableError {
	public var isCancelled = true
}

extension Error {
	public var isCancelled: Bool {
		do {
			throw self
		} catch let error as CancellableError {
			return error.isCancelled
		} catch URLError.cancelled {
			return true
		} catch CocoaError.userCancelled {
			return true
		} catch {
			#if os(macOS) || os(iOS) || os(tvOS)
				let pair = { ($0.domain, $0.code) }(error as NSError)
				return pair == ("SKErrorDomain", 2)
			#else
				return false
			#endif
		}
	}
}

extension Result {
	/**
	```
	switch result {
	case .success(let value):
		print(value)
	case .failure where result.isCancelled:
		print("Cancelled")
	case .failure(let error):
		print(error)
	}
	```
	*/
	public var isCancelled: Bool {
		do {
			_ = try get()
			return false
		} catch {
			return error.isCancelled
		}
	}
}

// TODO: Find a way to reduce the number of overloads for `wrap()`.
final class Once {
	private var lock = os_unfair_lock()
	private var hasRun = false
	private var value: Any?

	/**
	Executes the given closure only once. (Thread-safe)

	Returns the value that the called closure returns the first (and only) time it's called.

	```
	final class Foo {
		private let once = Once()

		func bar() {
			once.run {
				print("Called only once")
			}
		}
	}

	let foo = Foo()
	foo.bar()
	foo.bar()
	```

	```
	func process(_ text: String) -> String {
		return text
	}

	let a = once.run {
		process("a")
	}

	let b = once.run {
		process("b")
	}

	print(a, b)
	//=> "a a"
	```
	*/
	func run<T>(_ closure: () throws -> T) rethrows -> T {
		os_unfair_lock_lock(&lock)
		defer {
			os_unfair_lock_unlock(&lock)
		}

		guard !hasRun else {
			return value as! T
		}

		hasRun = true

		let returnValue = try closure()
		value = returnValue
		return returnValue
	}

	// TODO: Support any number of arguments when Swift supports variadics.
	/// Wraps a single-argument function.
	func wrap<T, U>(_ function: @escaping ((T) -> U)) -> ((T) -> U) {
		return { parameter in
			self.run {
				function(parameter)
			}
		}
	}

	/// Wraps an optional single-argument function.
	func wrap<T, U>(_ function: ((T) -> U)?) -> ((T) -> U)? {
		guard let function = function else {
			return nil
		}

		return { parameter in
			self.run {
				function(parameter)
			}
		}
	}

	/// Wraps a single-argument throwing function.
	func wrap<T, U>(_ function: @escaping ((T) throws -> U)) -> ((T) throws -> U) {
		return { parameter in
			try self.run {
				try function(parameter)
			}
		}
	}

	/// Wraps an optional single-argument throwing function.
	func wrap<T, U>(_ function: ((T) throws -> U)?) -> ((T) throws -> U)? {
		guard let function = function else {
			return nil
		}

		return { parameter in
			try self.run {
				try function(parameter)
			}
		}
	}
}

extension NSResponder {
	/// Presents the error in the given window if it's not nil, otherwise falls back to an app-modal dialog.
	open func presentError(_ error: Error, modalFor window: NSWindow?) {
		guard let window = window else {
			presentError(error)
			return
		}

		presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
	}
}

extension NSSharingService {
	class func share(items: [Any], from button: NSButton, preferredEdge: NSRectEdge = .maxX) {
		let sharingServicePicker = NSSharingServicePicker(items: items)
		sharingServicePicker.show(relativeTo: button.bounds, of: button, preferredEdge: preferredEdge)
	}
}

extension CALayer {
	// TODO: Make this one more generic by accepting a `x` parameter too.
	func animateScaleMove(fromScale: CGFloat, fromY: CGFloat) {
		let springAnimation = CASpringAnimation(keyPath: #keyPath(CALayer.transform))

		var tr = CATransform3DIdentity
		tr = CATransform3DTranslate(tr, bounds.size.width / 2, fromY, 0)
		tr = CATransform3DScale(tr, fromScale, fromScale, 1)
		tr = CATransform3DTranslate(tr, -bounds.size.width / 2, -bounds.size.height / 2, 0)

		springAnimation.damping = 15
		springAnimation.mass = 0.9
		springAnimation.initialVelocity = 1
		springAnimation.duration = springAnimation.settlingDuration

		springAnimation.fromValue = NSValue(caTransform3D: tr)
		springAnimation.toValue = NSValue(caTransform3D: CATransform3DIdentity)

		add(springAnimation, forKey: "")
	}
}

extension Error {
	var isNsError: Bool {
		return type(of: self) is NSError.Type
	}
}

extension NSError {
	// TODO: Return `Self` here in Swift 5.1
	class func from(error: Error, userInfo: [String: Any] = [:]) -> NSError {
		let nsError = error as NSError

		// Since Error and NSError are often bridged between each other, we check if it was originally an NSError and then return that.
		guard !error.isNsError else {
			guard !userInfo.isEmpty else {
				return nsError
			}

			// TODO: Use `Self` instead of `NSError` here in Swift 5.1
			return nsError.appending(userInfo: userInfo)
		}

		var userInfo = userInfo
		userInfo[NSLocalizedDescriptionKey] = error.localizedDescription

		// This is needed as `localizedDescription` often lacks important information, for example, when an NSError is wrapped in a Swift.Error.
		userInfo["Swift.Error"] = "\(nsError.domain).\(error)"

		// Awful, but no better way to get the enum case name.
		// This gets `Error.generateFrameFailed` from `Error.generateFrameFailed(Error Domain=AVFoundationErrorDomain Code=-11832 […]`.
		let errorName = "\(error)".split(separator: "(").first ?? ""

		return self.init(
			domain: "\(App.id) - \(nsError.domain)\(errorName.isEmpty ? "" : ".")\(errorName)",
			code: nsError.code,
			userInfo: userInfo
		)
	}

	/**
	- Parameter domainPostfix: String to append to the `domain`.
	*/
	class func appError(message: String, userInfo: [String: Any] = [:], domainPostfix: String? = nil) -> Self {
		return self.init(
			domain: domainPostfix != nil ? "\(App.id) - \(domainPostfix!)" : App.id,
			code: 0,
			userInfo: [NSLocalizedDescriptionKey: message]
		)
	}

	/// Returns a new error with the user info appended.
	func appending(userInfo newUserInfo: [String: Any]) -> Self {
		// TODO: Use `Self` here in Swift 5.1
		return type(of: self).init(
			domain: domain,
			code: code,
			userInfo: userInfo.appending(newUserInfo)
		)
	}
}

extension Dictionary {
	/// Adds the elements of the given dictionary to a copy of self and returns that.
	/// Identical keys in the given dictionary overwrites keys in the copy of self.
	func appending(_ dictionary: [Key: Value]) -> [Key: Value] {
		var newDictionary = self

		for (key, value) in dictionary {
			newDictionary[key] = value
		}

		return newDictionary
	}
}

#if canImport(Crashlytics)
	import Crashlytics

	extension Crashlytics {
		/// A better error recording method. Captures more debug info.
		static func recordNonFatalError(error: Error, userInfo: [String: Any] = [:]) {
			#if !DEBUG
				// This forces Crashlytics to actually provide some useful info for Swift errors
				let nsError = NSError.from(error: error, userInfo: userInfo)

				sharedInstance().recordError(nsError)
			#endif
		}

		static func recordNonFatalError(title: String? = nil, message: String) {
			#if !DEBUG
				sharedInstance().recordError(NSError.appError(message: message, domainPostfix: title))
			#endif
		}

		/// Set a value for a for a key to be associated with your crash data which will be visible in Crashlytics.
		static func record(key: String, value: Any?) {
			#if !DEBUG
				sharedInstance().setObjectValue(value, forKey: key)
			#endif
		}
	}

	extension NSAlert {
		/// Show a modal alert sheet on a window, or as an app-model alert if the given window is nil, and also report it as a non-fatal error to Crashlytics.
		@discardableResult
		static func showModalAndReportToCrashlytics(
			for window: NSWindow? = nil,
			message: String,
			informativeText: String? = nil,
			style: NSAlert.Style = .warning,
			debugInfo: String
		) -> NSApplication.ModalResponse {
			Crashlytics.recordNonFatalError(
				title: message,
				message: debugInfo
			)

			return NSAlert.showModal(
				for: window,
				message: message,
				informativeText: informativeText,
				style: style
			)
		}
	}
#endif

enum FileType {
	case png
	case jpeg
	case heic
	case tiff
	case gif

	static func from(fileExtension: String) -> FileType {
		switch fileExtension {
		case "png":
			return .png
		case "jpg", "jpeg":
			return .jpeg
		case "heic":
			return .heic
		case "tif", "tiff":
			return .tiff
		case "gif":
			return .gif
		default:
			fatalError("Unsupported file type")
		}
	}

	static func from(url: URL) -> FileType {
		return from(fileExtension: url.pathExtension)
	}

	var name: String {
		switch self {
		case .png:
			return "PNG"
		case .jpeg:
			return "JPEG"
		case .heic:
			return "HEIC"
		case .tiff:
			return "TIFF"
		case .gif:
			return "GIF"
		}
	}

	var identifier: String {
		switch self {
		case .png:
			return "public.png"
		case .jpeg:
			return "public.jpeg"
		case .heic:
			return "public.heic"
		case .tiff:
			return "public.tiff"
		case .gif:
			return "com.compuserve.gif"
		}
	}

	var fileExtension: String {
		switch self {
		case .png:
			return "png"
		case .jpeg:
			return "jpg"
		case .heic:
			return "heic"
		case .tiff:
			return "tiff"
		case .gif:
			return "gif"
		}
	}
}

extension Sequence {
	/**
	Returns the sum of elements in a sequence by mapping the elements with a numerator

	```
	[1, 2, 3].sum { $0 == 1 ? 10 : $0 }
	//=> 15
	```
	*/
	func sum<T: Numeric>(_ numerator: (Element) throws -> T) rethrows -> T {
		var result: T = 0
		for element in self {
			result += try numerator(element)
		}
		return result
	}
}

extension BinaryFloatingPoint {
	func rounded(
		toDecimalPlaces decimalPlaces: Int,
		rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero
	) -> Self {
		guard decimalPlaces >= 0 else {
			return self
		}
		var divisor: Self = 1
		for _ in 0..<decimalPlaces { divisor *= 10 }
		return (self * divisor).rounded(rule) / divisor
	}
}

extension QLPreviewPanel {
	func toggle() {
		if isVisible {
			orderOut(nil)
		} else {
			makeKeyAndOrderFront(nil)
		}
	}
}

extension NSView {
	/// Get the view frame in screen coordinates.
	var boundsInScreenCoordinates: CGRect? {
		return window?.convertToScreen(convert(bounds, to: nil))
	}
}
