import Cocoa
import AVFoundation
import class Quartz.QLPreviewPanel
import Defaults

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


func delay(seconds: TimeInterval, closure: @escaping () -> Void) {
	DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: closure)
}


struct Meta {
	static func openSubmitFeedbackPage() {
		let metadata =
			"""
			\(App.name) \(App.versionWithBuild) - \(App.id)
			macOS \(System.osVersion)
			\(System.hardwareModel)
			"""

		let query: [String: String] = [
			"product": App.name,
			"metadata": metadata
		]

		URL(string: "https://sindresorhus.com/feedback/")!.addingDictionaryAsQuery(query).open()
	}
}


extension NSView {
	func shake(duration: TimeInterval = 0.3, direction: NSUserInterfaceLayoutOrientation) {
		let translation = direction == .horizontal ? "x" : "y"
		let animation = CAKeyframeAnimation(keyPath: "transform.translation.\(translation)")
		animation.timingFunction = .linear
		animation.duration = duration
		animation.values = [-5, 5, -2.5, 2.5, 0]
		layer?.add(animation, forKey: nil)
	}
}


/// This is useful as `awakeFromNib` is not called for programatically created views.
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
	// Helper.
	private static func centeredOnScreen(rect: CGRect) -> CGRect {
		guard let screen = NSScreen.main else {
			return rect
		}

		// Looks better than perfectly centered.
		let yOffset = 0.12

		return rect.centered(in: screen.visibleFrame, xOffsetPercent: 0, yOffsetPercent: yOffset)
	}

	static let defaultContentSize = CGSize(width: 480, height: 300)

	static var defaultContentRect: CGRect {
		centeredOnScreen(rect: defaultContentSize.cgRect)
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

	/// Moves the window to the center of the screen, slightly more in the center than `window#center()`.
	func centerNatural() {
		setFrame(NSWindow.centeredOnScreen(rect: frame), display: true)
	}
}


extension NSWindowController {
	/// Expose the `view` like in NSViewController.
	var view: NSView? { window?.contentView }
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
		// So there seems to be a visual effect view already created by NSWindow.
		// If we can attach ourselves to it and make it a vibrant one - awesome.
		// If not, let's just add our view as a first one so it is vibrant anyways.
		if let visualEffectView = contentView?.superview?.subviews.compactMap({ $0 as? NSVisualEffectView }).first {
			visualEffectView.blendingMode = .behindWindow
			visualEffectView.material = .underWindowBackground
		} else {
			contentView?.superview?.insertVibrancyView(material: .underWindowBackground)
		}
	}
}


extension NSWindow {
	var toolbarView: NSView? { standardWindowButton(.closeButton)?.superview }
	var titlebarView: NSView? { toolbarView?.superview }
	var titlebarHeight: Double { Double(titlebarView?.bounds.height ?? 0) }
}


// swiftlint:disable:next identifier_name
private func __windowSheetPosition(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: CGRect) -> CGRect {
	// Adjust sheet position so it goes below the traffic lights.
	if window.styleMask.contains(.fullSizeContentView) {
		return rect.offsetBy(dx: 0, dy: CGFloat(-window.titlebarHeight))
	}

	return rect
}

/// - Note: Ensure you set `window.delegate = self` in the NSWindowController subclass.
extension NSWindowController: NSWindowDelegate {
	public func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: CGRect) -> CGRect {
		__windowSheetPosition(window, willPositionSheet: sheet, using: rect)
	}
}


extension NSView {
	private final class AddedToSuperviewObserverView: NSView {
		var onAdded: (() -> Void)?

		override var acceptsFirstResponder: Bool { false }

		convenience init() {
			self.init(frame: .zero)
		}

		override func viewDidMoveToWindow() {
			guard window != nil else {
				return
			}

			onAdded?()
			removeFromSuperview()
		}
	}

	func onAddedToSuperview(_ closure: @escaping () -> Void) {
		let view = AddedToSuperviewObserverView()
		view.onAdded = closure
		addSubview(view)
	}
}


extension NSAlert {
	/// Show an alert as a window-modal sheet, or as an app-modal (window-indepedendent) alert if the window is `nil` or not given.
	@discardableResult
	static func showModal(
		for window: NSWindow? = nil,
		message: String,
		informativeText: String? = nil,
		detailText: String? = nil,
		style: Style = .warning,
		buttonTitles: [String] = []
	) -> NSApplication.ModalResponse {
		NSAlert(
			message: message,
			informativeText: informativeText,
			detailText: detailText,
			style: style,
			buttonTitles: buttonTitles
		).runModal(for: window)
	}

	convenience init(
		message: String,
		informativeText: String? = nil,
		detailText: String? = nil,
		style: Style = .warning,
		buttonTitles: [String] = []
	) {
		self.init()
		self.messageText = message
		self.alertStyle = style

		if let informativeText = informativeText {
			self.informativeText = informativeText
		}

		if let detailText = detailText {
			let scrollView = NSTextView.scrollableTextView()

			// We're setting the frame manually here as it's impossible to use auto-layout,
			// since it has nothing to constrain to. This will eventually be rewritten in SwiftUI anyway.
			scrollView.frame = CGRect(width: 300, height: 120)

			scrollView.onAddedToSuperview {
				if let messageTextField = (scrollView.superview?.superview?.subviews.first { $0 is NSTextField }) {
					scrollView.frame.width = messageTextField.frame.width
				} else {
					assertionFailure("Couldn't detect the message textfield view of the NSAlert panel")
				}
			}

			let textView = scrollView.documentView as! NSTextView
			textView.drawsBackground = false
			textView.isEditable = false
			textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
			textView.textColor = .secondaryLabelColor
			textView.string = detailText

			self.accessoryView = scrollView
		}

		self.addButtons(withTitles: buttonTitles)
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

	/// Adds buttons with the given titles to the alert.
	func addButtons(withTitles buttonTitles: [String]) {
		for buttonTitle in buttonTitles {
			addButton(withTitle: buttonTitle)
		}
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
	Apple-recommended scale for video.

	```
	CMTime(seconds: (1 / fps), preferredTimescale: .video)
	```
	*/
	static let video: CMTimeScale = 600
}


extension Comparable {
	/// Note: It's not possible to implement `Range` or `PartialRangeUpTo` here as we can't know what `1.1..<1.53` would be. They only work with Stridable in our case.

	/// Example: 20.5.clamped(from: 10.3, to: 15)
	func clamped(from lowerBound: Self, to upperBound: Self) -> Self {
		min(max(self, lowerBound), upperBound)
	}

	/// Example: 20.5.clamped(to: 10.3...15)
	func clamped(to range: ClosedRange<Self>) -> Self {
		clamped(from: range.lowerBound, to: range.upperBound)
	}

	/// Example: 20.5.clamped(to: ...10.3)
	/// => 10.3
	func clamped(to range: PartialRangeThrough<Self>) -> Self {
		min(self, range.upperBound)
	}

	/// Example: 5.5.clamped(to: 10.3...)
	/// => 10.3
	func clamped(to range: PartialRangeFrom<Self>) -> Self {
		max(self, range.lowerBound)
	}
}

extension Strideable where Stride: SignedInteger {
	/// Example: 20.clamped(to: 5..<10)
	/// => 9
	func clamped(to range: CountableRange<Self>) -> Self {
		clamped(from: range.lowerBound, to: range.upperBound.advanced(by: -1))
	}

	/// Example: 20.clamped(to: 5...10)
	/// => 10
	func clamped(to range: CountableClosedRange<Self>) -> Self {
		clamped(from: range.lowerBound, to: range.upperBound)
	}

	/// Example: 20.clamped(to: ..<10)
	/// => 9
	func clamped(to range: PartialRangeUpTo<Self>) -> Self {
		min(self, range.upperBound.advanced(by: -1))
	}
}


extension FixedWidthInteger {
	/// Returns the integer formatted as a human readble file size.
	/// Example: `2.3 GB`
	var bytesFormattedAsFileSize: String {
		ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
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


// TODO: Make this a `BinaryFloatingPoint` extension instead.
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
		truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
	}
}

extension CGFloat {
	var formatted: String { Double(self).formatted }
}


extension CGSize {
	/// Example: `140×100`
	var formatted: String { "\(width.formatted)×\(height.formatted)" }
}


extension NSImage {
	/// `UIImage` polyfill.
	convenience init(cgImage: CGImage) {
		let size = CGSize(width: cgImage.width, height: cgImage.height)
		self.init(cgImage: cgImage, size: size)
	}
}


extension CGImage {
	var nsImage: NSImage { NSImage(cgImage: self) }
}


extension AVAssetImageGenerator {
	func image(at time: CMTime) -> NSImage? {
		(try? copyCGImage(at: time, actualTime: nil))?.nsImage
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
	var frameRate: Double? { Double(nominalFrameRate) }

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
		guard let rawDescription = formatDescriptions.first else {
			return nil
		}

		return CMFormatDescriptionGetMediaSubType(rawDescription as! CMFormatDescription).toString()
	}

	var codec: AVFormat? {
		guard let codecString = codecString else {
			return nil
		}

		return AVFormat(fourCC: codecString)
	}

	/// Returns a debug string with the media format.
	/// Example: `vide/avc1`
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


extension AVAssetTrack {
	/// Whether the track's duration is the same as the total asset duration.
	var isFullDuration: Bool { timeRange.duration == asset?.duration }

	/**
	Extract the track into a new AVAsset.

	This can be useful if you only want the video or audio of an asset. For example, sometimes the video track duration is shorter than the total asset duration. Extracting the track into a new asset ensures the asset duration is only as long as the video track duration.
	*/
	func extractToNewAsset() -> AVAsset? {
		let composition = AVMutableComposition()

		guard
			let track = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid),
			((try? track.insertTimeRange(CMTimeRange(start: .zero, duration: timeRange.duration), of: self, at: .zero)) != nil)
		else {
			return nil
		}

		track.preferredTransform = preferredTransform

		return composition
	}
}


/*
> FOURCC is short for "four character code" - an identifier for a video codec, compression format, color or pixel format used in media files.
*/
extension FourCharCode {
	/// Create a String representation of a FourCC.
	func toString() -> String {
		let a_ = self >> 24
		let b_ = self >> 16
		let c_ = self >> 8
		let d_ = self

		let bytes: [CChar] = [
			CChar(a_ & 0xff),
			CChar(b_ & 0xff),
			CChar(c_ & 0xff),
			CChar(d_ & 0xff),
			0
		]

		// Swift type-checking is too slow for this...
		//		let bytes: [CChar] = [
		//			CChar((self >> 24) & 0xff),
		//			CChar((self >> 16) & 0xff),
		//			CChar((self >> 8) & 0xff),
		//			CChar(self & 0xff),
		//			0
		//		]

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
		[
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
		"\(description) (\(fourCC.trimmingCharacters(in: .whitespaces)))"
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
	var hasVideo: Bool { !tracks(withMediaType: .video).isEmpty }

	/// Returns a boolean of whether there are any audio tracks.
	var hasAudio: Bool { !tracks(withMediaType: .audio).isEmpty }

	/// Returns the first video track if any.
	var firstVideoTrack: AVAssetTrack? { tracks(withMediaType: .video).first }

	/// Returns the first audio track if any.
	var firstAudioTrack: AVAssetTrack? { tracks(withMediaType: .audio).first }

	/// Returns the dimensions of the first video track if any.
	var dimensions: CGSize? { firstVideoTrack?.dimensions }

	/// Returns the frame rate of the first video track if any.
	var frameRate: Double? { firstVideoTrack?.frameRate }

	/// Returns the aspect ratio of the first video track if any.
	var aspectRatio: Double? { firstVideoTrack?.aspectRatio }

	/// Returns the video codec of the first video track if any.
	var videoCodec: AVFormat? { firstVideoTrack?.codec }

	/// Returns the audio codec of the first audio track if any.
	/// Example: `aac`
	var audioCodec: String? { firstAudioTrack?.codecString }

	/// The file size of the asset in bytes.
	/// - Note: If self is an `AVAsset` and not an `AVURLAsset`, the file size will just be an estimate.
	var fileSize: Int {
		guard let urlAsset = self as? AVURLAsset else {
			return tracks.sum { $0.estimatedFileSize }
		}

		return urlAsset.url.fileSize
	}

	var fileSizeFormatted: String { fileSize.bytesFormattedAsFileSize }
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


/// Video metadata.
extension AVAsset {
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
			fileSize: fileSize
		)
	}
}
extension URL {
	var videoMetadata: AVAsset.VideoMetadata? { AVURLAsset(url: self).videoMetadata }

	var isVideoDecodable: Bool { AVAsset(url: self).isVideoDecodable }
}


extension NSView {
	func center(inView view: NSView) {
		translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			centerXAnchor.constraint(equalTo: view.centerXAnchor),
			centerYAnchor.constraint(equalTo: view.centerYAnchor)
		])
	}

	func centerX(inView view: NSView) {
		translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			centerXAnchor.constraint(equalTo: view.centerXAnchor)
		])
	}

	func centerY(inView view: NSView) {
		translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			centerYAnchor.constraint(equalTo: view.centerYAnchor)
		])
	}

	func addSubviewToCenter(_ view: NSView) {
		addSubview(view)
		view.center(inView: superview!)
	}

	func constrainEdgesToSuperview(with insets: NSEdgeInsets = .zero) {
		guard let superview = superview else {
			assertionFailure("There is no superview for this view")
			return
		}

		superview.translatesAutoresizingMaskIntoConstraints = false
		translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: insets.left),
			trailingAnchor.constraint(equalTo: superview.trailingAnchor, constant: -insets.right),
			topAnchor.constraint(equalTo: superview.topAnchor, constant: insets.top),
			bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: -insets.bottom)
		])
	}

	func constrain(to size: CGSize) {
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: size.width),
			heightAnchor.constraint(equalToConstant: size.height)
		])
	}
}


extension NSView {
	/**
	Used to map logical edges to its representing `NSView` layout anchors.
	This type can be used for all auto-layout functions.
	*/
	struct ConstraintEdge {
		enum Vertical {
			case top
			case bottom

			fileprivate var constraintKeyPath: KeyPath<NSView, NSLayoutYAxisAnchor> {
				switch self {
				case .top:
					return \.topAnchor
				case .bottom:
					return \.bottomAnchor
				}
			}
		}

		enum Horizontal {
			case left
			case right

			fileprivate var constraintKeyPath: KeyPath<NSView, NSLayoutXAxisAnchor> {
				switch self {
				case .left:
					return \.leftAnchor
				case .right:
					return \.rightAnchor
				}
			}
		}
	}

	/**
	Sets constraints to match the given edges of this view and the given view.

	- parameter verticalEdge: The vertical edge to match with the given view.
	- parameter horizontalEdge: The horizontal edge to match with the given view.
	- parameter padding: The constant for the constraint.
	*/
	func constrainToEdges(
		verticalEdge: ConstraintEdge.Vertical? = nil,
		horizontalEdge: ConstraintEdge.Horizontal? = nil,
		view: NSView,
		padding: Double = 0
	) {
		translatesAutoresizingMaskIntoConstraints = false

		var constraints = [NSLayoutConstraint]()

		if let verticalEdge = verticalEdge {
			constraints.append(
				self[keyPath: verticalEdge.constraintKeyPath].constraint(equalTo: view[keyPath: verticalEdge.constraintKeyPath], constant: CGFloat(padding))
			)
		}

		if let horizontalEdge = horizontalEdge {
			constraints.append(
				self[keyPath: horizontalEdge.constraintKeyPath].constraint(equalTo: view[keyPath: horizontalEdge.constraintKeyPath], constant: CGFloat(padding))
			)
		}

		NSLayoutConstraint.activate(constraints)
	}
}


extension NSControl {
	/// Trigger the `.action` selector on the control.
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
	var size: Double {
		fontDescriptor.object(forKey: .size) as! Double
	}

	var traits: [NSFontDescriptor.TraitKey: AnyObject] {
		fontDescriptor.object(forKey: .traits) as! [NSFontDescriptor.TraitKey: AnyObject]
	}

	var weight: NSFont.Weight {
		NSFont.Weight(traits[.weight] as! CGFloat)
	}
}


/**
```
let foo = Label(text: "Foo")
```
*/
class Label: NSTextField {
	var text: String {
		get { stringValue }
		set {
			stringValue = newValue
		}
	}

	/// Allow the it to be disabled like other `NSControl`'s.
	override var isEnabled: Bool {
		didSet {
			textColor = isEnabled ? .controlTextColor : .disabledControlTextColor
		}
	}

	/// Support setting the text later with the `.text` property.
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


/// Use it in Interface Builder as a class or programmatically.
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
			self.font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(font.size), weight: font.weight)
		}
	}
}


extension NSView {
	/// UIKit polyfill.
	var center: CGPoint {
		get { frame.center }
		set {
			frame.center = newValue
		}
	}

	func centerInRect(_ rect: CGRect) {
		center = CGPoint(x: rect.midX, y: rect.midY)
	}

	/// Passing in a window can be useful when the view is not yet added to a window.
	/// If you don't pass in a window, it will use the window the view is in.
	func centerInWindow(_ window: NSWindow? = nil) {
		guard let view = (window ?? self.window)?.contentView else {
			return
		}

		centerInRect(view.bounds)
	}
}


/**
Mark unimplemented functions and have them fail with a useful message.

```
func foo() {
	unimplemented()
}

foo()
//=> "foo() in main.swift:1 has not been implemented"
```
*/
// swiftlint:disable:next unavailable_function
func unimplemented(
	function: StaticString = #function,
	file: String = #file,
	line: UInt = #line
) -> Never {
	fatalError("\(function) in \(file.nsString.lastPathComponent):\(line) has not been implemented")
}


extension NSPasteboard {
	/// Get the file URLs from dragged and dropped files.
	func fileURLs(types: [String] = []) -> [URL] {
		var options: [ReadingOptionKey: Any] = [
			.urlReadingFileURLsOnly: true
		]

		if !types.isEmpty {
			options[.urlReadingContentsConformToTypes] = types
		}

		guard
			let urls = readObjects(forClasses: [NSURL.self], options: options) as? [URL]
		else {
			return []
		}

		return urls
	}
}


/// Subclass this in Interface Builder with the title "Send Feedback…".
final class FeedbackMenuItem: NSMenuItem {
	required init(coder decoder: NSCoder) {
		super.init(coder: decoder)

		onAction = { _ in
			Meta.openSubmitFeedbackPage()
		}
	}
}


/// Subclass this in Interface Builder and set the `Url` field there.
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
			objc_getAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque()) as! T?
		} set {
			objc_setAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque(), newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
		}
	}
}


/// Identical to above, but for NSMenuItem.
extension NSMenuItem {
	typealias ActionClosure = ((NSMenuItem) -> Void)

	private struct AssociatedKeys {
		static let onActionClosure = AssociatedObject<ActionClosure>()
	}

	@objc
	private func callClosureGifski(_ sender: NSMenuItem) {
		onAction?(sender)
	}

	/**
	Closure version of `.action`.

	```
	let menuItem = NSMenuItem(title: "Unicorn")

	menuItem.onAction = { sender in
		print("NSMenuItem action: \(sender)")
	}
	```
	*/
	var onAction: ActionClosure? {
		get { AssociatedKeys.onActionClosure[self] }
		set {
			AssociatedKeys.onActionClosure[self] = newValue
			action = #selector(callClosureGifski)
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
	private func callClosureGifski(_ sender: NSControl) {
		onAction?(sender)
	}

	/**
	Closure version of `.action`.

	```
	let button = NSButton(title: "Unicorn", target: nil, action: nil)

	button.onAction = { sender in
		print("Button action: \(sender)")
	}
	```
	*/
	var onAction: ActionClosure? {
		get { AssociatedKeys.onActionClosure[self] }
		set {
			AssociatedKeys.onActionClosure[self] = newValue
			action = #selector(callClosureGifski)
			target = self
		}
	}
}


extension CAMediaTimingFunction {
	// TODO: Use `Self` here when using Swift 5.2.
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
	func addSubviewByFadingIn(
		_ view: NSView,
		duration: TimeInterval = 1,
		completion: (() -> Void)? = nil
	) {
		NSAnimationContext.runAnimationGroup({ context in
			context.duration = duration
			animator().addSubview(view)
		}, completionHandler: completion)
	}

	func removeSubviewByFadingOut(
		_ view: NSView,
		duration: TimeInterval = 1,
		completion: (() -> Void)? = nil
	) {
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

	func fadeIn(
		duration: TimeInterval = 1,
		delay: TimeInterval = 0,
		completion: (() -> Void)? = nil
	) {
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

	func fadeOut(
		duration: TimeInterval = 1,
		delay: TimeInterval = 0,
		completion: (() -> Void)? = nil
	) {
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
	// `NSString` has some useful properties that `String` does not.
	var nsString: NSString { self as NSString }
}


struct App {
	static let id = Bundle.main.bundleIdentifier!
	static let name = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
	static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
	static let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
	static let versionWithBuild = "\(version) (\(build))"

	static let isFirstLaunch: Bool = {
		let key = "SS_hasLaunched"

		// TODO: Remove this at some point.
		// Prevents showing "first launch" stuff for existing users.
		guard Defaults[.successfulConversionsCount] == 0 else {
			UserDefaults.standard.set(true, forKey: key)
			return false
		}

		if UserDefaults.standard.bool(forKey: key) {
			return false
		} else {
			UserDefaults.standard.set(true, forKey: key)
			return true
		}
	}()
}


/// Convenience for opening URLs.
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
		map {
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
	var directoryURL: Self { deletingLastPathComponent() }

	var directory: String { directoryURL.path }

	var filename: String {
		get { lastPathComponent }
		set {
			deleteLastPathComponent()
			appendPathComponent(newValue)
		}
	}

	var fileExtension: String {
		get { pathExtension }
		set {
			deletePathExtension()
			appendPathExtension(newValue)
		}
	}

	var filenameWithoutExtension: String {
		get { deletingPathExtension().lastPathComponent }
		set {
			let fileExtension = pathExtension
			deleteLastPathComponent()
			appendPathComponent(newValue)
			appendPathExtension(fileExtension)
		}
	}

	func changingFileExtension(to fileExtension: String) -> Self {
		var url = self
		url.fileExtension = fileExtension
		return url
	}

	func addingDictionaryAsQuery(_ dict: [String: String]) -> Self {
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

	/// File UTI.
	var typeIdentifier: String? { resourceValue(forKey: .typeIdentifierKey) }

	/// File size in bytes.
	var fileSize: Int { resourceValue(forKey: .fileSizeKey) ?? 0 }

	var fileSizeFormatted: String {
		ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
	}

	var exists: Bool { FileManager.default.fileExists(atPath: path) }

	var isReadable: Bool { boolResourceValue(forKey: .isReadableKey) }
}


extension URL {
	/**
	Check if the file conforms to the given type identifier.

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
	var isVideo: Bool { conformsTo(typeIdentifier: kUTTypeMovie as String) }
}


extension CGSize {
	static func * (lhs: Self, rhs: Double) -> Self {
		.init(width: lhs.width * CGFloat(rhs), height: lhs.height * CGFloat(rhs))
	}

	static func * (lhs: Self, rhs: CGFloat) -> Self {
		.init(width: lhs.width * rhs, height: lhs.height * rhs)
	}

	init(widthHeight: CGFloat) {
		self.init(width: widthHeight, height: widthHeight)
	}

	var cgRect: CGRect { .init(origin: .zero, size: self) }

	func aspectFit(to boundingSize: CGSize) -> Self {
		let ratio = min(boundingSize.width / width, boundingSize.height / height)
		return self * ratio
	}

	func aspectFit(to widthHeight: CGFloat) -> Self {
		aspectFit(to: Self(width: widthHeight, height: widthHeight))
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
		get { origin.x }
		set {
			origin.x = newValue
		}
	}

	var y: CGFloat {
		get { origin.y }
		set {
			origin.y = newValue
		}
	}

	/// `width` and `height` are defined in Foundation as getters only. We add support for setters too.
	/// These will not work when imported as a framework: https://bugs.swift.org/browse/SR-4017
	var width: CGFloat {
		get { size.width }
		set {
			size.width = newValue
		}
	}

	var height: CGFloat {
		get { size.height }
		set {
			size.height = newValue
		}
	}

	// MARK: - Edges

	var left: CGFloat {
		get { x }
		set {
			x = newValue
		}
	}

	var right: CGFloat {
		get { x + width }
		set {
			x = newValue - width
		}
	}

	var top: CGFloat {
		get { y + height }
		set {
			y = newValue - height
		}
	}

	var bottom: CGFloat {
		get { y }
		set {
			y = newValue
		}
	}

	// MARK: -

	var center: CGPoint {
		get { CGPoint(x: midX, y: midY) }
		set {
			origin = CGPoint(
				x: newValue.x - (size.width / 2),
				y: newValue.y - (size.height / 2)
			)
		}
	}

	var centerX: CGFloat {
		get { midX }
		set {
			center = CGPoint(x: newValue, y: midY)
		}
	}

	var centerY: CGFloat {
		get { midY }
		set {
			center = CGPoint(x: midX, y: newValue)
		}
	}

	/**
	Returns a `CGRect` where `self` is centered in `rect`.
	*/
	func centered(
		in rect: Self,
		xOffset: Double = 0,
		yOffset: Double = 0
	) -> Self {
		.init(
			x: ((rect.width - size.width) / 2) + CGFloat(xOffset),
			y: ((rect.height - size.height) / 2) + CGFloat(yOffset),
			width: size.width,
			height: size.height
		)
	}

	/**
	Returns a CGRect where `self` is centered in `rect`.

	- Parameters:
		- xOffsetPercent: The offset in percentage of `rect.width`.
	*/
	func centered(
		in rect: Self,
		xOffsetPercent: Double,
		yOffsetPercent: Double
	) -> Self {
		centered(
			in: rect,
			xOffset: Double(rect.width) * xOffsetPercent,
			yOffset: Double(rect.height) * yOffsetPercent
		)
	}
}


public protocol CancellableError: Error {
	/// Returns true if this Error represents a cancelled condition.
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
			let pair = { ($0.domain, $0.code) }(error as NSError)
			return pair == ("SKErrorDomain", 2)
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
		return { parameter in // swiftlint:disable:this implicit_return
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
		return { parameter in // swiftlint:disable:this implicit_return
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
	static func share(items: [Any], from button: NSButton, preferredEdge: NSRectEdge = .maxX) {
		let sharingServicePicker = NSSharingServicePicker(items: items)
		sharingServicePicker.show(relativeTo: button.bounds, of: button, preferredEdge: preferredEdge)
	}
}


extension Double {
	var cgFloat: CGFloat { CGFloat(self) }
}

extension CGFloat {
	var double: Double { Double(self) }
}


extension CALayer {
	func animateScaleMove(fromScale: Double, fromX: Double? = nil, fromY: Double? = nil) {
		let fromX = fromX?.cgFloat ?? bounds.size.width / 2
		let fromY = fromY?.cgFloat ?? bounds.size.height / 2

		let springAnimation = CASpringAnimation(keyPath: #keyPath(CALayer.transform))

		var tr = CATransform3DIdentity
		tr = CATransform3DTranslate(tr, fromX, fromY, 0)
		tr = CATransform3DScale(tr, CGFloat(fromScale), CGFloat(fromScale), 1)
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
	var isNsError: Bool { Self.self is NSError.Type }
}


extension NSError {
	static func from(error: Error, userInfo: [String: Any] = [:]) -> NSError {
		let nsError = error as NSError

		// Since Error and NSError are often bridged between each other, we check if it was originally an NSError and then return that.
		guard !error.isNsError else {
			guard !userInfo.isEmpty else {
				return nsError
			}

			return nsError.appending(userInfo: userInfo)
		}

		var userInfo = userInfo
		userInfo[NSLocalizedDescriptionKey] = error.localizedDescription

		// This is needed as `localizedDescription` often lacks important information, for example, when an NSError is wrapped in a Swift.Error.
		userInfo["Swift.Error"] = "\(nsError.domain).\(error)"

		// Awful, but no better way to get the enum case name.
		// This gets `Error.generateFrameFailed` from `Error.generateFrameFailed(Error Domain=AVFoundationErrorDomain Code=-11832 […]`.
		let errorName = "\(error)".split(separator: "(").first ?? ""

		return .init(
			domain: "\(App.id) - \(nsError.domain)\(errorName.isEmpty ? "" : ".")\(errorName)",
			code: nsError.code,
			userInfo: userInfo
		)
	}

	/**
	- Parameter domainPostfix: String to append to the `domain`.
	*/
	static func appError(
		message: String,
		userInfo: [String: Any] = [:],
		domainPostfix: String? = nil
	) -> Self {
		.init(
			domain: domainPostfix != nil ? "\(App.id) - \(domainPostfix!)" : App.id,
			code: 0,
			userInfo: [NSLocalizedDescriptionKey: message]
		)
	}

	/// Returns a new error with the user info appended.
	func appending(userInfo newUserInfo: [String: Any]) -> Self {
		.init(
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
		// This forces Crashlytics to actually provide some useful info for Swift errors.
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
		style: Style = .warning,
		debugInfo: String
	) -> NSApplication.ModalResponse {
		Crashlytics.recordNonFatalError(
			title: message,
			message: debugInfo
		)

		return Self.showModal(
			for: window,
			message: message,
			informativeText: informativeText,
			detailText: debugInfo,
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

	static func from(fileExtension: String) -> Self {
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

	static func from(url: URL) -> Self {
		from(fileExtension: url.pathExtension)
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
	Returns the sum of elements in a sequence by mapping the elements with a numerator.

	```
	[1, 2, 3].sum { $0 == 1 ? 10 : $0 }
	//=> 15
	```
	*/
	func sum<T: AdditiveArithmetic>(_ numerator: (Element) throws -> T) rethrows -> T {
		var result = T.zero

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

extension CGSize {
	func rounded(_ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Self {
		Self(width: width.rounded(rule), height: height.rounded(rule))
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
		window?.convertToScreen(convert(bounds, to: nil))
	}
}


extension Collection {
	/// Returns the element at the specified index if it is within bounds, otherwise nil.
	subscript(safe index: Index) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}


protocol Copyable {
	init(instance: Self)
}

extension Copyable {
	func copy() -> Self {
		Self(instance: self)
	}
}


// Source: https://github.com/apple/swift-evolution/blob/9940e45977e2006a29eccccddf6b62305758c5c3/proposals/0259-approximately-equal.md
// swiftlint:disable all
extension FloatingPoint {
	/// Test approximate equality with relative tolerance.
	///
	/// Do not use this function to check if a number is approximately
	/// zero; no reasoned relative tolerance can do what you want for
	/// that case. Use `isAlmostZero` instead for that case.
	///
	/// The relation defined by this predicate is symmetric and reflexive
	/// (except for NaN), but *is not* transitive. Because of this, it is
	/// often unsuitable for use for key comparisons, but it can be used
	/// successfully in many other contexts.
	///
	/// The internet is full advice about what not to do when comparing
	/// floating-point values:
	///
	/// - "Never compare floats for equality."
	/// - "Always use an epsilon."
	/// - "Floating-point values are always inexact."
	///
	/// Much of this advice is false, and most of the rest is technically
	/// correct but misleading. Almost none of it provides specific and
	/// correct recommendations for what you *should* do if you need to
	/// compare floating-point numbers.
	///
	/// There is no uniformly correct notion of "approximate equality", and
	/// there is no uniformly correct tolerance that can be applied without
	/// careful analysis. This function considers two values to be almost
	/// equal if the relative difference between them is smaller than the
	/// specified `tolerance`.
	///
	/// The default value of `tolerance` is `sqrt(.ulpOfOne)`; this value
	/// comes from the common numerical analysis wisdom that if you don't
	/// know anything about a computation, you should assume that roughly
	/// half the bits may have been lost to rounding. This is generally a
	/// pretty safe choice of tolerance--if two values that agree to half
	/// their bits but are not meaningfully almost equal, the computation
	/// is likely ill-conditioned and should be reformulated.
	///
	/// For more complete guidance on an appropriate choice of tolerance,
	/// consult with a friendly numerical analyst.
	///
	/// - Parameters:
	///   - other: the value to compare with `self`
	///   - tolerance: the relative tolerance to use for the comparison.
	///     Should be in the range (.ulpOfOne, 1).
	///
	/// - Returns: `true` if `self` is almost equal to `other`; otherwise
	///   `false`.
	@inlinable
	public func isAlmostEqual(
		to other: Self,
		tolerance: Self = Self.ulpOfOne.squareRoot()
	) -> Bool {
		// tolerances outside of [.ulpOfOne,1) yield well-defined but useless results,
		// so this is enforced by an assert rathern than a precondition.
		assert(tolerance >= .ulpOfOne && tolerance < 1, "tolerance should be in [.ulpOfOne, 1).")
		// The simple computation below does not necessarily give sensible
		// results if one of self or other is infinite; we need to rescale
		// the computation in that case.
		guard self.isFinite && other.isFinite else {
			return rescaledAlmostEqual(to: other, tolerance: tolerance)
		}
		// This should eventually be rewritten to use a scaling facility to be
		// defined on FloatingPoint suitable for hypot and scaled sums, but the
		// following is good enough to be useful for now.
		let scale = max(abs(self), abs(other), .leastNormalMagnitude)
		return abs(self - other) < scale*tolerance
	}

	/// Test if this value is nearly zero with a specified `absoluteTolerance`.
	///
	/// This test uses an *absolute*, rather than *relative*, tolerance,
	/// because no number should be equal to zero when a relative tolerance
	/// is used.
	///
	/// Some very rough guidelines for selecting a non-default tolerance for
	/// your computation can be provided:
	///
	/// - If this value is the result of floating-point additions or
	///   subtractions, use a tolerance of `.ulpOfOne * n * scale`, where
	///   `n` is the number of terms that were summed and `scale` is the
	///   magnitude of the largest term in the sum.
	///
	/// - If this value is the result of floating-point multiplications,
	///   consider each term of the product: what is the smallest value that
	///   should be meaningfully distinguished from zero? Multiply those terms
	///   together to get a tolerance.
	///
	/// - More generally, use half of the smallest value that should be
	///   meaningfully distinct from zero for the purposes of your computation.
	///
	/// For more complete guidance on an appropriate choice of tolerance,
	/// consult with a friendly numerical analyst.
	///
	/// - Parameter absoluteTolerance: values with magnitude smaller than
	///   this value will be considered to be zero. Must be greater than
	///   zero.
	///
	/// - Returns: `true` if `abs(self)` is less than `absoluteTolerance`.
	///            `false` otherwise.
	@inlinable
	public func isAlmostZero(
		absoluteTolerance tolerance: Self = Self.ulpOfOne.squareRoot()
		) -> Bool {
		assert(tolerance > 0)
		return abs(self) < tolerance
	}

	/// Rescales self and other to give meaningful results when one of them
	/// is infinite. We also handle NaN here so that the fast path doesn't
	/// need to worry about it.
	@usableFromInline
	internal func rescaledAlmostEqual(to other: Self, tolerance: Self) -> Bool {
		// NaN is considered to be not approximately equal to anything, not even
		// itself.
		if self.isNaN || other.isNaN { return false }
		if self.isInfinite {
			if other.isInfinite { return self == other }
			// Self is infinite and other is finite. Replace self with the binade
			// of the greatestFiniteMagnitude, and reduce the exponent of other by
			// one to compensate.
			let scaledSelf = Self(sign: self.sign,
								  exponent: Self.greatestFiniteMagnitude.exponent,
								  significand: 1)
			let scaledOther = Self(sign: .plus,
								   exponent: -1,
								   significand: other)
			// Now both values are finite, so re-run the naive comparison.
			return scaledSelf.isAlmostEqual(to: scaledOther, tolerance: tolerance)
		}
		// If self is finite and other is infinite, flip order and use scaling
		// defined above, since this relation is symmetric.
		return other.rescaledAlmostEqual(to: self, tolerance: tolerance)
	}
}
// swiftlint:enable all


extension NSEdgeInsets {
	static let zero = NSEdgeInsetsZero

	init(
		top: Double = 0,
		left: Double = 0,
		bottom: Double = 0,
		right: Double = 0
	) {
		self.init()
		self.top = CGFloat(top)
		self.left = CGFloat(left)
		self.bottom = CGFloat(bottom)
		self.right = CGFloat(right)
	}

	init(all: Double) {
		self.init(
			top: all,
			left: all,
			bottom: all,
			right: all
		)
	}

	var vertical: Double { Double(top + bottom) }
	var horizontal: Double { Double(left + right) }
}


extension NSControl {
	func focus() {
		window?.makeFirstResponder(self)
	}
}


extension URL {
	enum MetadataKey {
		/// The app used to create the file, for example, `Gifski 2.0.0`, `QuickTime Player 10.5`, etc.
		case itemCreator

		var attributeKey: String {
			switch self {
			case .itemCreator:
				return kMDItemCreator as String
			}
		}
	}

	func setMetadata<T>(key: MetadataKey, value: T) throws {
		try attributes.set("com.apple.metadata:\(key.attributeKey)", value: value)
	}
}


extension URLComponents {
	var queryDictionary: [String: String] {
		queryItems?.reduce(into: [String: String]()) { result, item in
			result[item.name] = item.value
		} ?? [:]
	}
}

extension URL {
	var components: URLComponents? {
		URLComponents(url: self, resolvingAgainstBaseURL: true)
	}

	var queryDictionary: [String: String] { components?.queryDictionary ?? [:] }
}


extension NSViewController {
	func push(viewController: NSViewController, completion: (() -> Void)? = nil) {
		guard let window = view.window else {
			return
		}

		let newOrigin = CGPoint(x: window.frame.midX - viewController.view.frame.width / 2.0, y: window.frame.midY - viewController.view.frame.height / 2.0)
		let newWindowFrame = CGRect(origin: newOrigin, size: viewController.view.frame.size)

		viewController.view.alphaValue = 0.0
		NSAnimationContext.runAnimationGroup({ _ in
			window.contentViewController?.view.animator().alphaValue = 0.0
			window.contentViewController = nil
			window.animator().setFrame(newWindowFrame, display: true)
		}, completionHandler: {
			window.contentViewController = viewController
			viewController.view.animator().alphaValue = 1.0
			completion?()
		})
	}

	func add(childController: NSViewController) {
		add(childController: childController, to: view)
	}

	func add(childController: NSViewController, to view: NSView) {
		addChild(childController)
		view.addSubview(childController.view)
		childController.view.constrainEdgesToSuperview()
	}
}


extension NSView {
	/// Get a subview matching a condition.
	func firstSubview(where matches: (NSView) -> Bool, deep: Bool = false) -> NSView? {
		for subview in subviews {
			if matches(subview) {
				return subview
			}

			if deep, let match = subview.firstSubview(where: matches, deep: deep) {
				return match
			}
		}

		return nil
	}
}


extension NSLayoutConstraint {
	/// Returns copy of the constraint with changed properties provided as arguments.
	func changing(
		firstItem: Any? = nil,
		firstAttribute: Attribute? = nil,
		relation: Relation? = nil,
		secondItem: NSView? = nil,
		secondAttribute: Attribute? = nil,
		multiplier: Double? = nil,
		constant: Double? = nil
	) -> Self {
		.init(
			item: firstItem ?? self.firstItem as Any,
			attribute: firstAttribute ?? self.firstAttribute,
			relatedBy: relation ?? self.relation,
			toItem: secondItem ?? self.secondItem,
			attribute: secondAttribute ?? self.secondAttribute,
			multiplier: multiplier.flatMap(CGFloat.init) ?? self.multiplier,
			constant: constant.flatMap(CGFloat.init) ?? self.constant
		)
	}
}


extension NSObject {
	/// Returns the class name.
	static let simpleClassName = String(describing: self)

	/// Returns the class name of the instance.
	var simpleClassName: String { Self.simpleClassName }
}


extension CMTime {
	/// Get the `CMTime` as a duration from zero to the seconds value of `self`.
	/// Can be `nil` when the `.duration` is not available, for example, when an asset has not yet been fully loaded or if it's a live stream.
	var durationRange: ClosedRange<Double>? {
		guard isNumeric else {
			return nil
		}

		return 0...seconds
	}
}


extension CMTimeRange {
	/// Get `self` as a range in seconds.
	/// Can be `nil` when the range is not available, for example, when an asset has not yet been fully loaded or if it's a live stream.
	var range: ClosedRange<Double>? {
		guard
			start.isNumeric,
			end.isNumeric
		else {
			return nil
		}

		return start.seconds...end.seconds
	}
}


extension AVPlayerItem {
	/// The duration range of the item.
	/// Can be `nil` when the `.duration` is not available, for example, when the asset has not yet been fully loaded or if it's a live stream.
	var durationRange: ClosedRange<Double>? { duration.durationRange }

	/// The playable range of the item.
	/// Can be `nil` when the `.duration` is not available, for example, when the asset has not yet been fully loaded or if it's a live stream.
	var playbackRange: ClosedRange<Double>? {
		get {
			guard let range = durationRange else {
				return nil
			}

			let startTime = reversePlaybackEndTime.isNumeric ? reversePlaybackEndTime.seconds : range.lowerBound
			let endTime = forwardPlaybackEndTime.isNumeric ? forwardPlaybackEndTime.seconds : range.upperBound

			return startTime < endTime ? startTime...endTime : endTime...startTime
		}
		set {
			guard let range = newValue else {
				return
			}

			forwardPlaybackEndTime = CMTime(seconds: range.upperBound, preferredTimescale: .video)
			reversePlaybackEndTime = CMTime(seconds: range.lowerBound, preferredTimescale: .video)
		}
	}
}


extension FileManager {
	/// Copy a file and optionally overwrite the destination if it exists.
	func copyItem(
		at sourceURL: URL,
		to destinationURL: URL,
		overwrite: Bool = false
	) throws {
		if overwrite {
			try? removeItem(at: destinationURL)
		}

		try copyItem(at: sourceURL, to: destinationURL)
	}
}


extension ClosedRange where Bound: AdditiveArithmetic {
	/// Get the length between the lower and upper bound.
	var length: Bound { upperBound - lowerBound }
}

extension ClosedRange {
	/**
	Returns true if `self` is a superset of the given range.

	```
	(1.0...1.5).isSuperset(of: 1.2...1.3)
	//=> true
	```
	*/
	func isSuperset(of other: ClosedRange<Bound>) -> Bool {
		other.isEmpty ||
			(
				lowerBound <= other.lowerBound &&
				other.upperBound <= upperBound
			)
	}

	/**
	Returns true if `self` is a subset of the given range.

	```
	(1.2...1.3).isSubset(of: 1.0...1.5)
	//=> true
	```
	*/
	func isSubset(of other: ClosedRange<Bound>) -> Bool {
		other.isSuperset(of: self)
	}
}

extension ClosedRange where Bound == Double {
	// TODO: Add support for negative ranges.
	/**
	Make a new range where the length (difference between the lower and upper bound) is at least the given amount.

	The use-case for this method is being able to ensure a sub-range inside a range is of a certain size.

	It will first try to expand on both the lower and upper bound, and if not possible, it will expand the lower bound, and if that is not possible, it will expand the upper bound. If the resulting range is larger than the given `fullRange`, it will be clamped to `fullRange`.

	- Precondition: The range and the given range must be positive.
	- Precondition: The range must be a subset of the given range.

	```
	(1...1.2).minimumRangeLength(of: 1, in: 0...4)
	//=> 0.5...1.7

	(0...0.5).minimumRangeLength(of: 1, in: 0...4)
	//=> 0...1

	(3.5...4).minimumRangeLength(of: 1, in: 0...4)
	//=> 3...4

	(0...0.1).minimumRangeLength(of: 1, in: 0...4)
	//=> 0...1
	```
	*/
	func minimumRangeLength(of length: Bound, in fullRange: Self) -> Self {
		guard length > self.length else {
			return self
		}

		assert(isSubset(of: fullRange), "`self` must be a subset of the given range")
		assert(lowerBound >= 0 && upperBound >= 0, "`self` must the positive")
		assert(fullRange.lowerBound >= 0 && fullRange.upperBound >= 0, "The given range must be positive")

		let lower = lowerBound - (length / 2)
		let upper = upperBound + (length / 2)

		if
			fullRange.contains(lower),
			fullRange.contains(upper)
		{
			return lower...upper
		}

		if
			!fullRange.contains(lower),
			fullRange.contains(upper)
		{
			return fullRange.lowerBound...length
		}

		if
			fullRange.contains(lower),
			!fullRange.contains(upper)
		{
			return (fullRange.upperBound - length)...fullRange.upperBound
		}

		return self
	}
}


extension BinaryInteger {
	var isEven: Bool { isMultiple(of: 2) }
	var isOdd: Bool { !isEven }
}


extension AppDelegate {
	static let shared = NSApp.delegate as! AppDelegate
}


final class LaunchCompletions {
	private static var shouldAddObserver = true
	private static var shouldRunInstantly = false
	private static var finishedLaunchingCompletions = [() -> Void]()

	static func add(_ completion: @escaping () -> Void) {
		finishedLaunchingCompletions.append(completion)

		if shouldAddObserver {
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(runFinishedLaunchingCompletions),
				name: NSApplication.didFinishLaunchingNotification,
				object: nil
			)

			shouldAddObserver = false
		}

		if shouldRunInstantly {
			runFinishedLaunchingCompletions()
		}
	}

	static func applicationDidLaunch() {
		shouldAddObserver = false
		shouldRunInstantly = true
	}

	@objc
	private static func runFinishedLaunchingCompletions() {
		for completion in finishedLaunchingCompletions {
			completion()
		}

		finishedLaunchingCompletions = []
	}
}


@IBDesignable
final class BackButton: NSButton {
	convenience init() {
		self.init()
		commonInit()
	}

	override func awakeFromNib() {
		super.awakeFromNib()
		commonInit()
	}

	private func commonInit() {
		self.image = NSImage(named: NSImage.goBackTemplateName)
	}
}


extension NSResponder {
	// This method is internally implemented on `NSResponder` as `Error` is generic which comes with many limitations.
	fileprivate func presentErrorAsSheet(
		_ error: Error,
		for window: NSWindow,
		didPresent: (() -> Void)?
	) {
		final class DelegateHandler {
			var didPresent: (() -> Void)?

			@objc
			func didPresentHandler() {
				didPresent?()
			}
		}

		let delegate = DelegateHandler()
		delegate.didPresent = didPresent

		presentError(
			error,
			modalFor: window,
			delegate: delegate,
			didPresent: #selector(delegate.didPresentHandler),
			contextInfo: nil
		)
	}
}

extension Error {
	/// Present the error as an async sheet on the given window.
	/// - Note: This exists because the built-in `NSResponder#presentError(forModal:)` method requires too many arguments, selector as callback, and it says it's modal but it's not blocking, which is surprising.
	func presentAsSheet(for window: NSWindow, didPresent: (() -> Void)?) {
		NSApp.presentErrorAsSheet(self, for: window, didPresent: didPresent)
	}

	/// Present the error as a blocking modal sheet on the given window.
	/// If the window is nil, the error will be presented in an app-level modal dialog.
	func presentAsModalSheet(for window: NSWindow?) {
		guard let window = window else {
			presentAsModal()
			return
		}

		presentAsSheet(for: window) {
			NSApp.stopModal()
		}

		NSApp.runModal(for: window)
	}

	/// Present the error as a blocking app-level modal dialog.
	func presentAsModal() {
		NSApp.presentError(self)
	}
}
