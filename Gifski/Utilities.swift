import SwiftUI
import Combine
import AVFoundation
import class Quartz.QLPreviewPanel
import StoreKit.SKStoreReviewController
import Accelerate.vImage
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
class SSView: NSView { // swiftlint:disable:this final_class
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
		material: NSVisualEffectView.Material,
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
	private enum AssociatedKeys {
		static let cancellable = ObjectAssociation<AnyCancellable?>()
	}

	func makeVibrant() {
		// So there seems to be a visual effect view already created by NSWindow.
		// If we can attach ourselves to it and make it a vibrant one - awesome.
		// If not, let's just add our view as a first one so it is vibrant anyways.
		guard let visualEffectView = contentView?.superview?.subviews.lazy.compactMap({ $0 as? NSVisualEffectView }).first else {
			contentView?.superview?.insertVibrancyView(material: .underWindowBackground)
			return
		}

		visualEffectView.blendingMode = .behindWindow
		visualEffectView.material = .underWindowBackground

		AssociatedKeys.cancellable[self] = visualEffectView.publisher(for: \.effectiveAppearance)
			.sink { _ in
				visualEffectView.blendingMode = .behindWindow
				visualEffectView.material = .underWindowBackground
			}
	}
}


extension NSWindow {
	var toolbarView: NSView? { standardWindowButton(.closeButton)?.superview }
	var titlebarView: NSView? { toolbarView?.superview }
	var titlebarHeight: Double { Double(titlebarView?.bounds.height ?? 0) }
}


// TODO: Remove these when targeting macOS 11.
private func __windowSheetPosition(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: CGRect) -> CGRect {
	if #available(macOS 11, *) {
		return rect
	}

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
		title: String,
		message: String? = nil,
		detailText: String? = nil,
		style: Style = .warning,
		buttonTitles: [String] = [],
		defaultButtonIndex: Int? = nil
	) -> NSApplication.ModalResponse {
		NSAlert(
			title: title,
			message: message,
			detailText: detailText,
			style: style,
			buttonTitles: buttonTitles,
			defaultButtonIndex: defaultButtonIndex
		).runModal(for: window)
	}

	/// The index in the `buttonTitles` array for the button to use as default.
	/// Set `-1` to not have any default. Useful for really destructive actions.
	var defaultButtonIndex: Int {
		get {
			buttons.firstIndex { $0.keyEquivalent == "\r" } ?? -1
		}
		set {
			// Clear the default button indicator from other buttons.
			for button in buttons where button.keyEquivalent == "\r" {
				button.keyEquivalent = ""
			}

			if newValue != -1 {
				buttons[newValue].keyEquivalent = "\r"
			}
		}
	}

	convenience init(
		title: String,
		message: String? = nil,
		detailText: String? = nil,
		style: Style = .warning,
		buttonTitles: [String] = [],
		defaultButtonIndex: Int? = nil
	) {
		self.init()
		self.messageText = title
		self.alertStyle = style

		if let message = message {
			self.informativeText = message
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
			textView.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
			textView.textColor = .secondaryLabelColor
			textView.string = detailText

			self.accessoryView = scrollView
		}

		addButtons(withTitles: buttonTitles)

		if let defaultButtonIndex = defaultButtonIndex {
			self.defaultButtonIndex = defaultButtonIndex
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
		let isFinishedIgnoreImage: Bool
	}

	/// - Note: If you use `result.completedCount`, don't forget to update its usage in each `completionHandler` call as it can change if frames are skipped, for example, blank frames.
	func generateCGImagesAsynchronously(
		forTimePoints timePoints: [CMTime],
		completionHandler: @escaping (Swift.Result<CompletionHandlerResult, Error>) -> Void
	) {
		let times = timePoints.map { NSValue(time: $0) }
		var totalCount = times.count
		var completedCount = 0
		var decodeFailureFrameCount = 0

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
							isFinished: completedCount == totalCount,
							isFinishedIgnoreImage: false
						)
					)
				)
			case .failed:
				// Handles blank frames in the middle of the video.
				// TODO: Report the `xcrun` bug to Apple if it's still an issue in macOS 11.
				if let error = error as? AVError {
					// Ugly workaround for when the last frame is a failure.
					func finishWithoutImageIfNeeded() {
						guard completedCount == totalCount else {
							return
						}

						completionHandler(
							.success(
								CompletionHandlerResult(
									image: .empty,
									requestedTime: requestedTime,
									actualTime: actualTime,
									completedCount: completedCount,
									totalCount: totalCount,
									isFinished: true,
									isFinishedIgnoreImage: true
								)
							)
						)
					}

					// We ignore blank frames.
					if error.code == .noImageAtTime {
						totalCount -= 1
						print("No image at time. Completed: \(completedCount) Total: \(totalCount)")
						finishWithoutImageIfNeeded()
						break
					}

					// macOS 11 (still an issue in macOS 11.2) started throwing “decode failed” error for some frames in screen recordings. As a workaround, we ignore these as the GIF seems fine still.
					if error.code == .decodeFailed {
						decodeFailureFrameCount += 1
						totalCount -= 1
						print("Decode failure. Completed: \(completedCount) Total: \(totalCount)")
						Crashlytics.recordNonFatalError(error: error, userInfo: ["requestedTime": requestedTime.seconds])
						finishWithoutImageIfNeeded()
						break
					}
				}

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
	static let video: Self = 600
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
	enum VideoTrimmingError: Error {
		case unknownAssetReaderFailure
		case videoTrackIsEmpty
		case assetIsMissingVideoTrack
		case compositionCouldNotBeCreated
	}

	/**
	Removes blank frames from the beginning of the track.

	This can be useful to trim blank frames from files produced by tools like the iOS simulator screen recorder.
	*/
	func trimmingBlankFrames() throws -> AVAssetTrack {
		// Create new composition
		let composition = AVMutableComposition()
		guard
			let wrappedTrack = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: .zero)
		else {
			throw VideoTrimmingError.compositionCouldNotBeCreated
		}
		try wrappedTrack.insertTimeRange(timeRange, of: self, at: .zero)

		let reader = try AVAssetReader(asset: composition)

		// Create reader for wrapped track.
		let readerOutput = AVAssetReaderTrackOutput(track: wrappedTrack, outputSettings: nil)
		reader.add(readerOutput)
		reader.startReading()

		defer {
			reader.cancelReading()
		}

		// Iterate through samples until we reach one with a non-zero size.
		while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
			guard [.completed, .reading].contains(reader.status) else {
				throw reader.error ?? VideoTrimmingError.unknownAssetReaderFailure
			}

			// On first non-empty frame.
			guard sampleBuffer.totalSampleSize == 0 else {
				let currentTimestamp = sampleBuffer.outputPresentationTimeStamp
				wrappedTrack.removeTimeRange(.init(start: .zero, end: currentTimestamp))
				return wrappedTrack
			}
		}

		throw VideoTrimmingError.videoTrackIsEmpty
	}
}


extension AVAssetTrack.VideoTrimmingError: LocalizedError {
	public var errorDescription: String? {
		switch self {
		case .unknownAssetReaderFailure:
			return "Asset could not be read."
		case .videoTrackIsEmpty:
			return "Video track is empty."
		case .assetIsMissingVideoTrack:
			return "Asset is missing video track."
		case .compositionCouldNotBeCreated:
			return "Composition could not be created."
		}
	}
}


extension AVAsset {
	typealias VideoTrimmingError = AVAssetTrack.VideoTrimmingError

	/**
	Removes blank frames from the beginning of the first video track of the asset. The returned asset only includes the first video track.

	This can be useful to trim blank frames from files produced by tools like the iOS simulator screen recorder.
	*/
	func trimmingBlankFramesFromFirstVideoTrack() throws -> AVAsset {
		guard let videoTrack = firstVideoTrack else {
			throw VideoTrimmingError.assetIsMissingVideoTrack
		}

		let trimmedTrack = try videoTrack.trimmingBlankFrames()

		guard let trimmedAsset = trimmedTrack.asset else {
			assertionFailure("Track is somehow missing asset")
			return AVMutableComposition()
		}

		return trimmedAsset
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
	var codecIdentifier: String? {
		guard
			let rawDescription = formatDescriptions.first
		else {
			return nil
		}

		// This is the only way to do it. It's guaranteed to be this type.
		// swiftlint:disable:next force_cast
		let formatDescription = rawDescription as! CMFormatDescription

		return CMFormatDescriptionGetMediaSubType(formatDescription).fourCharCodeToString()
	}

	var codec: AVFormat? {
		guard let codecString = codecIdentifier else {
			return nil
		}

		return AVFormat(fourCC: codecString)
	}

	/// Use this for presenting the codec to the user. This is either the codec name, if known, or the codec identifier. You can just default to `"Unknown"` if this is `nil`.
	var codecTitle: String? { codec?.description ?? codecIdentifier }

	/// Returns a debug string with the media format.
	/// Example: `vide/avc1`
	var mediaFormat: String {
		// This is the only way to do it. It's guaranteed to be this type.
		// swiftlint:disable:next force_cast
		let descriptions = formatDescriptions as! [CMFormatDescription]

		var format = [String]()
		for description in descriptions {
			// Get string representation of media type (vide, soun, sbtl, etc.)
			let type = CMFormatDescriptionGetMediaType(description).fourCharCodeToString()

			// Get string representation media subtype (avc1, aac, tx3g, etc.)
			let subType = CMFormatDescriptionGetMediaSubType(description).fourCharCodeToString()

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
			(try? track.insertTimeRange(CMTimeRange(start: .zero, duration: timeRange.duration), of: self, at: .zero)) != nil
		else {
			return nil
		}

		track.preferredTransform = preferredTransform

		return composition
	}
}

extension AVAssetTrack {
	struct VideoKeyframeInfo {
		let frameCount: Int
		let keyframeCount: Int

		var keyframeInterval: Double {
			Double(frameCount) / Double(keyframeCount)
		}

		var keyframeRate: Double {
			Double(keyframeCount) / Double(frameCount)
		}
	}

	func getKeyframeInfo() -> VideoKeyframeInfo? {
		guard
			let asset = asset,
			let reader = try? AVAssetReader(asset: asset)
		else {
			return nil
		}

		let trackReaderOutput = AVAssetReaderTrackOutput(track: self, outputSettings: nil)
		reader.add(trackReaderOutput)

		guard reader.startReading() else {
			return nil
		}

		var frameCount = 0
		var keyframeCount = 0

		while true {
			guard let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() else {
				reader.cancelReading()
				break
			}

			if sampleBuffer.numSamples > 0 {
				frameCount += 1

				if sampleBuffer.sampleAttachments.first?[.notSync] == nil {
					keyframeCount += 1
				}
			}
		}

		return VideoKeyframeInfo(frameCount: frameCount, keyframeCount: keyframeCount)
	}
}


/*
> FOURCC is short for "four character code" - an identifier for a video codec, compression format, color or pixel format used in media files.
*/
extension FourCharCode {
	/// Create a String representation of a FourCC.
	func fourCharCodeToString() -> String {
		let a_ = self >> 24
		let b_ = self >> 16
		let c_ = self >> 8
		let d_ = self

		let bytes: [CChar] = [
			CChar(a_ & 0xFF),
			CChar(b_ & 0xFF),
			CChar(c_ & 0xFF),
			CChar(d_ & 0xFF),
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


enum AVFormat: String {
	case hevc
	case h264
	case av1
	case vp9
	case appleProResRAWHQ
	case appleProResRAW
	case appleProRes4444XQ
	case appleProRes4444
	case appleProRes422HQ
	case appleProRes422
	case appleProRes422LT
	case appleProRes422Proxy
	case appleAnimation

	// https://hap.video/using-hap.html
	// https://github.com/Vidvox/hap/blob/master/documentation/HapVideoDRAFT.md#names-and-identifiers
	case hap1
	case hap5
	case hapY
	case hapM
	case hapA
	case hap7

	case cineFormHD

	// https://en.wikipedia.org/wiki/QuickTime_Graphics
	case quickTimeGraphics

	// https://en.wikipedia.org/wiki/Avid_DNxHD
	case avidDNxHD

	init?(fourCC: String) {
		switch fourCC.trimmingCharacters(in: .whitespaces) {
		case "hvc1":
			self = .hevc
		case "avc1":
			self = .h264
		case "av01":
			self = .av1
		case "vp09":
			self = .vp9
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
		case "Hap1":
			self = .hap1
		case "Hap5":
			self = .hap5
		case "HapY":
			self = .hapY
		case "HapM":
			self = .hapM
		case "HapA":
			self = .hapA
		case "Hap7":
			self = .hap7
		case "CFHD":
			self = .cineFormHD
		case "smc":
			self = .quickTimeGraphics
		case "AVdh":
			self = .avidDNxHD
		default:
			return nil
		}
	}

	init?(fourCC: FourCharCode) {
		self.init(fourCC: fourCC.fourCharCodeToString())
	}

	var fourCC: String {
		switch self {
		case .hevc:
			return "hvc1"
		case .h264:
			return "avc1"
		case .av1:
			return "av01"
		case .vp9:
			return "vp09"
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
		case .hap1:
			return "Hap1"
		case .hap5:
			return "Hap5"
		case .hapY:
			return "HapY"
		case .hapM:
			return "HapM"
		case .hapA:
			return "HapA"
		case .hap7:
			return "Hap7"
		case .cineFormHD:
			return "CFHD"
		case .quickTimeGraphics:
			return "smc"
		case .avidDNxHD:
			return "AVdh"
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

	/// - Important: This check only covers known (by us) compatible formats. It might be missing some. Don't use it for strict matching. Also keep in mind that even though a codec is supported, it might still not be decodable as the codec profile level might not be supported.
	var isSupported: Bool {
		self == .hevc || self == .h264 || isAppleProRes
	}
}

extension AVFormat: CustomStringConvertible {
	var description: String {
		switch self {
		case .hevc:
			return "HEVC"
		case .h264:
			return "H264"
		case .av1:
			return "AV1"
		case .vp9:
			return "VP9"
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
		case .hap1:
			return "Vidvox Hap"
		case .hap5:
			return "Vidvox Hap Alpha"
		case .hapY:
			return "Vidvox Hap Q"
		case .hapM:
			return "Vidvox Hap Q Alpha"
		case .hapA:
			return "Vidvox Hap Alpha-Only"
		case .hap7:
			// No official name for this.
			return "Vidvox Hap"
		case .cineFormHD:
			return "CineForm HD"
		case .quickTimeGraphics:
			return "QuickTime Graphics"
		case .avidDNxHD:
			return "Avid DNxHD"
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
		#if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
		case .metadataObject:
			return "Metadata objects"
		#endif
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
	var audioCodec: String? { firstAudioTrack?.codecIdentifier }

	/// The file size of the asset in bytes.
	/// - Note: If self is an `AVAsset` and not an `AVURLAsset`, the file size will just be an estimate.
	var fileSize: Int {
		guard let urlAsset = self as? AVURLAsset else {
			return tracks.sum(\.estimatedFileSize)
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
			Video codec: \(videoCodec?.debugDescription ?? firstVideoTrack?.codecIdentifier ?? "nil")
			Audio codec: \(describing: audioCodec)
			Duration: \(describing: durationFormatter.stringSafe(from: duration.seconds))
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
				Codec: \(describing: track.mediaType == .video ? track.codec?.debugDescription : track.codecIdentifier)
				Duration: \(describing: durationFormatter.stringSafe(from: track.timeRange.duration.seconds))
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
	enum ConstraintEdge {
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
	/// The point size of the font.
	var size: Double { Double(pointSize) }

	var traits: [NSFontDescriptor.TraitKey: AnyObject] {
		fontDescriptor.object(forKey: .traits) as! [NSFontDescriptor.TraitKey: AnyObject]
	}

	var weight: NSFont.Weight { .init(traits[.weight] as! CGFloat) }
}


/**
```
let foo = Label(text: "Foo")
```
*/
class Label: NSTextField { // swiftlint:disable:this final_class
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
		if let font = font {
			self.font = .monospacedDigitSystemFont(ofSize: CGFloat(font.size), weight: font.weight)
		}
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
func unimplemented(
	function: StaticString = #function,
	file: String = #fileID,
	line: Int = #line
) -> Never {
	fatalError("\(function) in \(file.nsString.lastPathComponent):\(line) has not been implemented")
}


extension NSPasteboard.PasteboardType {
	/// The name of the URL if you put a URL on the pasteboard.
	static let urlName = Self("public.url-name")
}

extension NSPasteboard.PasteboardType {
	/**
	Convention for getting the bundle identifier of the source app.

	> This marker’s presence indicates that the source of the content is the application with the bundle identifier matching its UTF–8 string content. For example: `pasteboard.setString("com.sindresorhus.Foo" forType: "org.nspasteboard.source")`. This is useful when the source is not the foreground application. This is meant to be shown to the user by a supporting app for informational purposes only. Note that an empty string is a valid value as explained below.
	> - http://nspasteboard.org
	*/
	static let sourceAppBundleIdentifier = Self("org.nspasteboard.source")
}

extension NSPasteboard {
	/**
	Add a marker to the pasteboard indicating which app put the current data on the pasteboard.

	This helps clipboard managers identity the source app.

	- Important: All pasteboard operation should call this, unless you use `NSPasteboard#with`.

	Read more: http://nspasteboard.org
	*/
	func setSourceApp() {
		setString(SSApp.id, forType: .sourceAppBundleIdentifier)
	}
}

extension NSPasteboard {
	/**
	Starts a new pasteboard writing session. Do all pasteboard write operations in the given closure.

	It takes care of calling `NSPasteboard#clearContents()` for you and also adds a marker for the source app (`NSPasteboard#setSourceApp()`).

	```
	NSPasteboard.general.with {
		$0.setString("Unicorn", forType: .string)
	}
	```
	*/
	func with(_ callback: (NSPasteboard) -> Void) {
		clearContents()
		callback(self)
		setSourceApp()
	}
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
			SSApp.openSendFeedbackPage()
		}
	}
}


/// Subclass this in Interface Builder and set the `Url` field there.
final class UrlMenuItem: NSMenuItem {
	@IBInspectable var url: String?

	required init(coder decoder: NSCoder) {
		super.init(coder: decoder)

		onAction = { [weak self] _ in
			guard
				let self = self,
				let url = self.url
			else {
				return
			}

			NSWorkspace.shared.open(URL(string: url)!)
		}
	}
}


enum AssociationPolicy {
	case assign
	case retainNonatomic
	case copyNonatomic
	case retain
	case copy

	var rawValue: objc_AssociationPolicy {
		switch self {
		case .assign:
			return .OBJC_ASSOCIATION_ASSIGN
		case .retainNonatomic:
			return .OBJC_ASSOCIATION_RETAIN_NONATOMIC
		case .copyNonatomic:
			return .OBJC_ASSOCIATION_COPY_NONATOMIC
		case .retain:
			return .OBJC_ASSOCIATION_RETAIN
		case .copy:
			return .OBJC_ASSOCIATION_COPY
		}
	}
}

final class ObjectAssociation<Value: Any> {
	private let defaultValue: Value
	private let policy: AssociationPolicy

	init(defaultValue: Value, policy: AssociationPolicy = .retainNonatomic) {
		self.defaultValue = defaultValue
		self.policy = policy
	}

	subscript(index: AnyObject) -> Value {
		get {
			objc_getAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque()) as? Value ?? defaultValue
		}
		set {
			objc_setAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque(), newValue, policy.rawValue)
		}
	}
}

extension ObjectAssociation {
	convenience init<T>(policy: AssociationPolicy = .retainNonatomic) where Value == T? {
		self.init(defaultValue: nil, policy: policy)
	}
}


/// Identical to above, but for NSMenuItem.
extension NSMenuItem {
	typealias ActionClosure = ((NSMenuItem) -> Void)

	private enum AssociatedKeys {
		static let onActionClosure = ObjectAssociation<ActionClosure?>()
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

	private enum AssociatedKeys {
		static let onActionClosure = ObjectAssociation<ActionClosure?>()
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
	static let `default` = CAMediaTimingFunction(name: .default)
	static let linear = CAMediaTimingFunction(name: .linear)
	static let easeIn = CAMediaTimingFunction(name: .easeIn)
	static let easeOut = CAMediaTimingFunction(name: .easeOut)
	static let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
}


extension NSView {
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
			animations: { [self] in
				isHidden = false
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
			animations: { [self] in
				alphaValue = 0
			},
			completion: { [self] in
				isHidden = true
				alphaValue = 1
				completion?()
			}
		)
	}
}


extension String {
	// `NSString` has some useful properties that `String` does not.
	var nsString: NSString { self as NSString }
}


extension NSAppearance {
	var isDarkMode: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}


enum SSApp {
	static let id = Bundle.main.bundleIdentifier!
	static let name = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
	static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
	static let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
	static let versionWithBuild = "\(version) (\(build))"

	static let isFirstLaunch: Bool = {
		let key = "SS_hasLaunched"

		if UserDefaults.standard.bool(forKey: key) {
			return false
		} else {
			UserDefaults.standard.set(true, forKey: key)
			return true
		}
	}()

	static var isDarkMode: Bool { NSApp.effectiveAppearance.isDarkMode }

	static func openSendFeedbackPage() {
		let metadata =
			"""
			\(SSApp.name) \(SSApp.versionWithBuild) - \(SSApp.id)
			macOS \(Device.osVersion)
			\(Device.hardwareModel)
			\(Device.architecture)
			"""

		let query: [String: String] = [
			"product": SSApp.name,
			"metadata": metadata
		]

		URL("https://sindresorhus.com/feedback/").settingQueryItems(from: query).open()
	}
}

extension SSApp {
	static func runOnce(identifier: String, _ execute: () -> Void) {
		let key = "SS_App_runOnce__\(identifier)"

		if !UserDefaults.standard.bool(forKey: key) {
			UserDefaults.standard.set(true, forKey: key)
			execute()
		}
	}
}


extension URL: ExpressibleByStringLiteral {
	/**
	Example:

	```
	let url: URL = "https://sindresorhus.com"
	```
	*/
	public init(stringLiteral value: StaticString) {
		self.init(string: "\(value)")!
	}
}

extension URL {
	/**
	Example:

	```
	URL("https://sindresorhus.com")
	```
	*/
	init(_ staticString: StaticString) {
		self.init(string: "\(staticString)")!
	}
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


enum Device {
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

	/**
	The CPU architecture.

	```
	Device.architecture
	//=> "arm64"
	```
	*/
	static let architecture: String = {
		var sysinfo = utsname()
		let result = uname(&sysinfo)

		guard result == EXIT_SUCCESS else {
			return "unknown"
		}

		let data = Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN))

		guard let identifier = String(bytes: data, encoding: .ascii) else {
			return "unknown"
		}

		return identifier.trimmingCharacters(in: .controlCharacters)
	}()

	static let isRunningNativelyOnMacWithAppleSilicon: Bool = {
		#if os(macOS) && arch(arm64)
		return true
		#else
		return false
		#endif
	}()

	static let supportedVideoTypes = [
		AVFileType.mp4.rawValue,
		AVFileType.m4v.rawValue,
		AVFileType.mov.rawValue
	]
}


typealias QueryDictionary = [String: String]


extension CharacterSet {
	/// Characters allowed to be unescaped in an URL
	/// https://tools.ietf.org/html/rfc3986#section-2.3
	static let urlUnreservedRFC3986 = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

/// This should really not be necessary, but it's at least needed for my `formspree.io` form...
/// Otherwise is results in "Internal Server Error" after submitting the form
/// Relevant: https://www.djackson.org/why-we-do-not-use-urlcomponents/
private func escapeQueryComponent(_ query: String) -> String {
	query.addingPercentEncoding(withAllowedCharacters: .urlUnreservedRFC3986)!
}


extension Dictionary where Key == String {
	/// This correctly escapes items. See `escapeQueryComponent`.
	var toQueryItems: [URLQueryItem] {
		map {
			URLQueryItem(
				name: escapeQueryComponent($0),
				value: escapeQueryComponent("\($1)")
			)
		}
	}

	var toQueryString: String {
		var components = URLComponents()
		components.queryItems = toQueryItems
		return components.query!
	}
}


extension Dictionary {
	func compactValues<T>() -> [Key: T] where Value == T? {
		compactMapValues { $0 }
	}
}


extension URLComponents {
	/// This correctly escapes items. See `escapeQueryComponent`.
	init?(string: String, query: QueryDictionary) {
		self.init(string: string)
		self.queryDictionary = query
	}

	/// This correctly escapes items. See `escapeQueryComponent`.
	var queryDictionary: QueryDictionary {
		get {
			queryItems?.toDictionary { ($0.name, $0.value) }.compactValues() ?? [:]
		}
		set {
			/// Using `percentEncodedQueryItems` instead of `queryItems` since the query items are already custom-escaped. See `escapeQueryComponent`.
			percentEncodedQueryItems = newValue.toQueryItems
		}
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

	/**
	Returns `self` with the given query dictionary merged in.

	The keys in the given dictionary overwrites any existing keys.
	*/
	func settingQueryItems(from queryDictionary: QueryDictionary) -> Self {
		guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
			return self
		}

		components.queryDictionary = components.queryDictionary.appending(queryDictionary)

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

//	var contentType: UTType? { resourceValue(forKey: .contentTypeKey) }

	/// File UTI.
	var typeIdentifier: String? { resourceValue(forKey: .typeIdentifierKey) }

	/// File size in bytes.
	var fileSize: Int { resourceValue(forKey: .fileSizeKey) ?? 0 }

	var fileSizeFormatted: String {
		ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
	}

	// TODO: Use the below instead when targeting macOS 10.15. Also in `AVAsset#fileSize`.
	/// File size in bytes.
//	var fileSize: Measurement<UnitInformationStorage> { Measurement<UnitInformationStorage>(value: resourceValue(forKey: .fileSizeKey) ?? 0, unit: .bytes) }
//
//	var fileSizeFormatted: String {
//		ByteCountFormatter.string(from: fileSize, countStyle: .file)
//	}

	var exists: Bool { FileManager.default.fileExists(atPath: path) }

	var isReadable: Bool { boolResourceValue(forKey: .isReadableKey) }

	var isWritable: Bool { boolResourceValue(forKey: .isWritableKey) }

	var isVolumeReadonly: Bool { boolResourceValue(forKey: .volumeIsReadOnlyKey) }
}


extension URL {
	/// Returns the user's real home directory when called in a sandboxed app.
	static let realHomeDirectory = Self(
		fileURLWithFileSystemRepresentation: getpwuid(getuid())!.pointee.pw_dir!,
		isDirectory: true,
		relativeTo: nil
	)
}


extension URL {
	func relationship(to url: Self) -> FileManager.URLRelationship {
		var relationship: FileManager.URLRelationship = .other
		_ = try? FileManager.default.getRelationship(&relationship, ofDirectoryAt: self, toItemAt: url)
		return relationship
	}
}


extension URL {
	/// Check whether the URL is inside the home directory.
	var isInsideHomeDirectory: Bool {
		Self.realHomeDirectory.relationship(to: self) == .contains
	}

	/**
	Check whether the URL path is on the main volume; The volume with the root file system.

	- Note: The URL does not need to exist.
	*/
	var isOnMainVolume: Bool {
		// We intentionally do a string check instead of `try? resourceValues(forKeys: [.volumeIsRootFileSystemKey]).volumeIsRootFileSystem` as it's faster and it works on URLs that doesn't exist.
		!path.hasPrefix("/Volumes/")
	}
}


extension URL {
	/// Whether the directory URL is suitable for use as a default directory for a save panel.
	var canBeDefaultSavePanelDirectory: Bool {
		// We allow if it's inside the home directory on the main volume or on a different writable volume.
		isInsideHomeDirectory || (!isOnMainVolume && !isVolumeReadonly)
	}
}


extension URL {
	/// Get various common system directories.
	static func systemDirectory(_ directory: FileManager.SearchPathDirectory) -> Self {
		// I don't think this can fail, but just in case, we have a sensible fallback.
		(try? FileManager.default.url(for: directory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? FileManager.default.homeDirectoryForCurrentUser
	}

	/**
	- Note: When sandboxed, this returns the directory inside the sandbox container, not in the user's home directory. However, NSSavePanel/NSOpenPanel handles it correctly.
	*/
	static let downloadsDirectory = systemDirectory(.downloadsDirectory)
}


// TODO: Use UTType when targeting macOS 11.
extension URL {
	/**
	Check if the file conforms to the given type identifier.

	```
	URL(fileURLWithPath: "video.mp4", isDirectory: false).conformsTo(typeIdentifier: "public.movie")
	//=> true
	```
	*/
	func conformsTo(typeIdentifier parentTypeIdentifier: String) -> Bool {
		guard let typeIdentifier = typeIdentifier else {
			return false
		}

		return UTTypeConformsTo(typeIdentifier as CFString, parentTypeIdentifier as CFString)
	}
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

	var longestSide: CGFloat { max(width, height) }

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
		{ [self] parameter in
			run {
				function(parameter)
			}
		}
	}

	/// Wraps an optional single-argument function.
	func wrap<T, U>(_ function: ((T) -> U)?) -> ((T) -> U)? {
		guard let function = function else {
			return nil
		}

		return { [self] parameter in
			run {
				function(parameter)
			}
		}
	}

	/// Wraps a single-argument throwing function.
	func wrap<T, U>(_ function: @escaping ((T) throws -> U)) -> ((T) throws -> U) {
		{ [self] parameter in
			try run {
				try function(parameter)
			}
		}
	}

	/// Wraps an optional single-argument throwing function.
	func wrap<T, U>(_ function: ((T) throws -> U)?) -> ((T) throws -> U)? {
		guard let function = function else {
			return nil
		}

		return { [self] parameter in
			try run {
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
			domain: "\(SSApp.id) - \(nsError.domain)\(errorName.isEmpty ? "" : ".")\(errorName)",
			code: nsError.code,
			userInfo: userInfo
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


extension NSError {
	/**
	Use this for generic app errors.

	- Note: Prefer using a specific enum-type error whenever possible.

	- Parameter description: The description of the error. This is shown as the first line in error dialogs.
	- Parameter recoverySuggestion: Explain how the user how they can recover from the error. For example, "Try choosing a different directory". This is usually shown as the second line in error dialogs.
	- Parameter userInfo: Metadata to add to the error. Can be a custom key or any of the `NSLocalizedDescriptionKey` keys except `NSLocalizedDescriptionKey` and `NSLocalizedRecoverySuggestionErrorKey`.
	- Parameter domainPostfix: String to append to the `domain` to make it easier to identify the error. The domain is the app's bundle identifier.
	*/
	static func appError(
		_ description: String,
		recoverySuggestion: String? = nil,
		userInfo: [String: Any] = [:],
		domainPostfix: String? = nil
	) -> Self {
		var userInfo = userInfo
		userInfo[NSLocalizedDescriptionKey] = description

		if let recoverySuggestion = recoverySuggestion {
			userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
		}

		return .init(
			domain: domainPostfix.map { "\(SSApp.id) - \($0)" } ?? SSApp.id,
			code: 1, // This is what Swift errors end up as.
			userInfo: userInfo
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


#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics

extension Crashlytics {
	/// A better error recording method. Captures more debug info.
	static func recordNonFatalError(error: Error, userInfo: [String: Any] = [:]) {
		#if !DEBUG
		// This forces Crashlytics to actually provide some useful info for Swift errors.
		let nsError = NSError.from(error: error, userInfo: userInfo)

		crashlytics().record(error: nsError)
		#endif
	}

	static func recordNonFatalError(title: String? = nil, message: String) {
		#if !DEBUG
		crashlytics().record(error: NSError.appError(message, domainPostfix: title))
		#endif
	}

	/// Set a value for a for a key to be associated with your crash data which will be visible in Crashlytics.
	static func record(key: String, value: Any?) {
		#if !DEBUG
		crashlytics().setCustomValue(value as Any, forKey: key)
		#endif
	}
}

extension NSAlert {
	/// Show a modal alert sheet on a window, or as an app-model alert if the given window is nil, and also report it as a non-fatal error to Crashlytics.
	@discardableResult
	static func showModalAndReportToCrashlytics(
		for window: NSWindow? = nil,
		title: String,
		message: String? = nil,
		style: Style = .warning,
		showDebugInfo: Bool = true,
		debugInfo: String
	) -> NSApplication.ModalResponse {
		Crashlytics.recordNonFatalError(
			title: title,
			message: debugInfo
		)

		return Self.showModal(
			for: window,
			title: title,
			message: message,
			detailText: showDebugInfo ? debugInfo : nil,
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


extension Sequence {
	/**
	Convert a sequence to a dictionary by mapping over the values and using the returned key as the key and the current sequence element as value.

	```
	[1, 2, 3].toDictionary { $0 }
	//=> [1: 1, 2: 2, 3: 3]
	```
	*/
	func toDictionary<Key: Hashable>(with pickKey: (Element) -> Key) -> [Key: Element] {
		var dictionary = [Key: Element]()
		for element in self {
			dictionary[pickKey(element)] = element
		}
		return dictionary
	}

	/**
	Convert a sequence to a dictionary by mapping over the elements and returning a key/value tuple representing the new dictionary element.

	```
	[(1, "a"), (2, "b")].toDictionary { ($1, $0) }
	//=> ["a": 1, "b": 2]
	```
	*/
	func toDictionary<Key: Hashable, Value>(with pickKeyValue: (Element) -> (Key, Value)) -> [Key: Value] {
		var dictionary = [Key: Value]()
		for element in self {
			let newElement = pickKeyValue(element)
			dictionary[newElement.0] = newElement.1
		}
		return dictionary
	}

	/**
	Same as the above but supports returning optional values.

	```
	[(1, "a"), (nil, "b")].toDictionary { ($1, $0) }
	//=> ["a": 1, "b": nil]
	```
	*/
	func toDictionary<Key: Hashable, Value>(with pickKeyValue: (Element) -> (Key, Value?)) -> [Key: Value?] {
		var dictionary = [Key: Value?]()
		for element in self {
			let newElement = pickKeyValue(element)
			dictionary[newElement.0] = newElement.1
		}
		return dictionary
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
		guard self.isFinite, other.isFinite else {
			return rescaledAlmostEqual(to: other, tolerance: tolerance)
		}
		// This should eventually be rewritten to use a scaling facility to be
		// defined on FloatingPoint suitable for hypot and scaled sums, but the
		// following is good enough to be useful for now.
		let scale = max(abs(self), abs(other), .leastNormalMagnitude)
		return abs(self - other) < scale * tolerance
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
			let scaledSelf = Self(
				sign: self.sign,
				exponent: Self.greatestFiniteMagnitude.exponent,
				significand: 1
			)
			let scaledOther = Self(
				sign: .plus,
				exponent: -1,
				significand: other
			)
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

		guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
			window.makeFirstResponder(viewController)

			DispatchQueue.main.async {
				window.contentViewController = nil
				window.setFrame(newWindowFrame, display: true)
				window.contentViewController = viewController
				completion?()
			}

			return
		}

		viewController.view.alphaValue = 0.0

		// Workaround for macOS first responder quirk. Still in macOS 10.15.3.
		// Reproduce: Without the below, if you click convert, hide the window, show the window when the conversion is done, and then drag and drop a new file, the width/height text fields are now not editable.
		window.makeFirstResponder(viewController)

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
	func firstSubview(deep: Bool = false, where matches: (NSView) -> Bool) -> NSView? {
		for subview in subviews {
			if matches(subview) {
				return subview
			}

			if deep, let match = subview.firstSubview(deep: deep, where: matches) {
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
	// Note: It's intentionally a getter to get the dynamic self.
	/// Returns the class name without module name.
	static var simpleClassName: String { String(describing: self) }

	/// Returns the class name of the instance without module name.
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
	func isSuperset(of other: Self) -> Bool {
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
	func isSubset(of other: Self) -> Bool {
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
		image = NSImage(named: NSImage.goBackTemplateName)
		setAccessibilityLabel("Back")
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


extension AVPlayer {
	/**
	Seek to the start of the playable range of the video.

	The start might not be at `0` if, for example, the video has been trimmed in `AVPlayerView` trim mode.
	*/
	func seekToStart() {
		let seconds = currentItem?.playbackRange?.lowerBound ?? 0

		seek(
			to: CMTime(seconds: seconds, preferredTimescale: .video),
			toleranceBefore: .zero,
			toleranceAfter: .zero
		)
	}

	/**
	Seek to the end of the playable range of the video.

	The start might not be at `duration` if, for example, the video has been trimmed in `AVPlayerView` trim mode.
	*/
	func seekToEnd() {
		guard let seconds = currentItem?.playbackRange?.upperBound ?? currentItem?.duration.seconds else {
			return
		}

		seek(
			to: CMTime(seconds: seconds, preferredTimescale: .video),
			toleranceBefore: .zero,
			toleranceAfter: .zero
		)
	}
}


final class LoopingPlayer: AVPlayer {
	private var cancellable: AnyCancellable?

	/// Loop the playback.
	var loopPlayback = false {
		didSet {
			updateObserver()
		}
	}

	/// Bounce the playback.
	var bouncePlayback = false {
		didSet {
			updateObserver()

			if !bouncePlayback, rate == -1 {
				rate = 1
			}
		}
	}

	private func updateObserver() {
		guard bouncePlayback || loopPlayback else {
			cancellable = nil
			actionAtItemEnd = .pause
			return
		}

		actionAtItemEnd = .none

		guard cancellable == nil else {
			// Already observing. No need to update.
			return
		}

		cancellable = NotificationCenter.default
			.publisher(for: .AVPlayerItemDidPlayToEndTime, object: currentItem)
			.sink { [weak self] _ in
				guard let self = self else {
					return
				}

				self.pause()

				if
					self.bouncePlayback, self.currentItem?.canPlayReverse == true,
					self.currentTime().seconds > self.currentItem?.playbackRange?.lowerBound ?? 0
				{
					self.seekToEnd()
					self.rate = -1
				} else if self.loopPlayback {
					self.seekToStart()
					self.rate = 1
				}
			}
	}
}


extension DateComponentsFormatter {
	/// Like `string(from: TimeInterval)` but does not cause an `NSInternalInconsistencyException` exception for `NaN` and `Infinity`.
	/// This is especially useful when formatting `CMTime#seconds` which can often be `NaN`.
	func stringSafe(from timeInterval: TimeInterval) -> String? {
		guard !timeInterval.isNaN else {
			return "NaN"
		}

		guard timeInterval.isFinite else {
			return "Infinity"
		}

		return string(from: timeInterval)
	}
}


extension Numeric {
	mutating func increment(by value: Self = 1) -> Self {
		self += value
		return self
	}

	mutating func decrement(by value: Self = 1) -> Self {
		self -= value
		return self
	}
}


extension SSApp {
	private static let key = Defaults.Key("SSApp_requestReview", default: 0)

	/// Requests a review only after this method has been called the given amount of times.
	static func requestReviewAfterBeingCalledThisManyTimes(_ counts: [Int]) {
		guard counts.contains(Defaults[key].increment()) else {
			return
		}

		SKStoreReviewController.requestReview()
	}
}


extension Sequence {
	/**
	Returns an array of elements split into groups of the given size.

	If it can't be split evenly, the final chunk will be the remaining elements.

	If the requested chunk size is larger than the sequence, the chunk will be smaller than requested.

	```
	[1, 2, 3, 4].chunked(by: 2)
	//=> [[1, 2], [3, 4]]
	```
	*/
	func chunked(by chunkSize: Int) -> [[Element]] {
		reduce(into: []) { result, current in
			if let last = result.last, last.count < chunkSize {
				result.append(result.removeLast() + [current])
			} else {
				result.append([current])
			}
		}
	}
}


extension Collection where Index == Int {
	/// Return a subset of the array of the given length by sampling "evenly distributed" elements.
	func sample(length: Int) -> [Element] {
		precondition(length >= 0, "The length cannot be negative.")

		guard length < count else {
			return Array(self)
		}

		return (0..<length).map { self[($0 * count + count / 2) / length] }
	}
}


final class AtomicDictionary<Key: Hashable, Value>: CustomDebugStringConvertible {
	private var storage = [Key: Value]()

	private let queue = DispatchQueue(
		label: "com.sindresorhus.AtomicDictionary.\(UUID().uuidString)",
		qos: .utility,
		attributes: .concurrent,
		autoreleaseFrequency: .inherit,
		target: .global()
	)

	subscript(key: Key) -> Value? {
		get {
			queue.sync { storage[key] }
		}
		set {
			queue.async(flags: .barrier) { [weak self] in
				self?.storage[key] = newValue
			}
		}
	}

	var debugDescription: String { storage.debugDescription }
}

/**
Debounce a function call.

Thread-safe.

```
final class Foo {
	private let debounce = Debouncer(delay: 0.2)

	func reset() {
		debounce(_reset)
	}

	private func _reset() {
		// …
	}
}
```

or

```
final class Foo {
	func reset() {
		Debouncer.debounce(delay: 0.2, _reset)
	}

	private func _reset() {
		// …
	}
}
```
*/
final class Debouncer {
	private let delay: TimeInterval
	private var workItem: DispatchWorkItem?

	init(delay: TimeInterval) {
		self.delay = delay
	}

	func callAsFunction(_ action: @escaping () -> Void) {
		workItem?.cancel()
		let newWorkItem = DispatchWorkItem(block: action)
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: newWorkItem)
		workItem = newWorkItem
	}
}

extension Debouncer {
	private static var debouncers = AtomicDictionary<String, Debouncer>()

	private static func debounce(
		identifier: String,
		delay: TimeInterval,
		action: @escaping () -> Void
	) {
		let debouncer = { () -> Debouncer in
			guard let debouncer = debouncers[identifier] else {
				let debouncer = self.init(delay: delay)
				debouncers[identifier] = debouncer
				return debouncer
			}

			return debouncer
		}()

		debouncer {
			debouncers[identifier] = nil
			action()
		}
	}

	/**
	Debounce a function call.

	This is less efficient than the instance method, but more convenient.

	Thread-safe.
	*/
	static func debounce(
		file: String = #fileID,
		function: StaticString = #function,
		line: Int = #line,
		delay: TimeInterval,
		action: @escaping () -> Void
	) {
		let identifier = "\(file)-\(function)-\(line)"
		debounce(identifier: identifier, delay: delay, action: action)
	}
}


extension Sequence where Element: Sequence {
	func flatten() -> [Element.Element] {
		flatMap { $0 }
	}
}


extension NSFont {
	/// Returns a new version of the font with the existing font descriptor replaced by the given font descriptor.
	func withDescriptor(_ descriptor: NSFontDescriptor) -> NSFont {
		// It's important that the size is `0` and not `pointSize` as otherwise the descriptor is not able to change the font size.
		Self(descriptor: descriptor, size: 0) ?? self
	}
}


extension String {
	var attributedString: NSAttributedString { NSAttributedString(string: self) }
}


extension NSAttributedString {
	static func + (lhs: NSAttributedString, rhs: NSAttributedString) -> NSAttributedString {
		let string = NSMutableAttributedString(attributedString: lhs)
		string.append(rhs)
		return string
	}

	static func + (lhs: NSAttributedString, rhs: String) -> NSAttributedString {
		lhs + NSAttributedString(string: rhs)
	}

	static func += (lhs: inout NSAttributedString, rhs: NSAttributedString) {
		// swiftlint:disable:next shorthand_operator
		lhs = lhs + rhs
	}

	static func += (lhs: inout NSAttributedString, rhs: String) {
		lhs += NSAttributedString(string: rhs)
	}

	var nsRange: NSRange { NSRange(0..<length) }

	var font: NSFont {
		attributeForWholeString(.font) as? NSFont ?? .systemFont(ofSize: NSFont.systemFontSize)
	}

	/// Get an attribute if it applies to the whole string.
	func attributeForWholeString(_ key: Key) -> Any? {
		guard length > 0 else {
			return nil
		}

		var foundRange = NSRange()
		let result = attribute(key, at: 0, longestEffectiveRange: &foundRange, in: nsRange)

		guard foundRange.length == length else {
			return nil
		}

		return result
	}

	/// Returns a `NSMutableAttributedString` version.
	func mutable() -> NSMutableAttributedString {
		// Force-casting here is safe as it can only be nil if there's no `mutableCopy` implementation, but we know there is for `NSMutableAttributedString`.
		// swiftlint:disable:next force_cast
		mutableCopy() as! NSMutableAttributedString
	}

	func addingAttributes(_ attributes: [Key: Any]) -> NSAttributedString {
		let new = mutable()
		new.addAttributes(attributes, range: nsRange)
		return new
	}

	func withColor(_ color: NSColor) -> NSAttributedString {
		addingAttributes([.foregroundColor: color])
	}

	func withFontSize(_ fontSize: Double) -> NSAttributedString {
		addingAttributes([.font: font.withSize(CGFloat(fontSize))])
	}
}


extension String {
	var trimmedTrailing: Self {
		replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
	}

	/**
	```
	"Unicorn".truncating(to: 4)
	//=> "Uni…"
	```
	*/
	func truncating(to number: Int, truncationIndicator: Self = "…") -> Self {
		if number <= 0 {
			return ""
		} else if count > number {
			return String(prefix(number - truncationIndicator.count)).trimmedTrailing + truncationIndicator
		} else {
			return self
		}
	}
}


extension NSExtensionContext {
	var inputItemsTyped: [NSExtensionItem] { inputItems as! [NSExtensionItem] }

	var attachments: [NSItemProvider] {
		inputItemsTyped.compactMap(\.attachments).flatten()
	}
}


extension UnsafeMutableRawPointer {
	/**
	Convert an unsafe mutable raw pointer to an array.

	```
	let bytes = sourceBuffer.data?.toArray(to: UInt8.self, capacity: Int(sourceBuffer.height) * sourceBuffer.rowBytes)
	```
	*/
	func toArray<T>(to type: T.Type, capacity count: Int) -> [T] {
		let pointer = bindMemory(to: type, capacity: count)
		return Array(UnsafeBufferPointer(start: pointer, count: count))
	}
}


extension Data {
	/// The bytes of the data.
	var bytes: [UInt8] { [UInt8](self) }
}


extension Array where Element == UInt8 {
	/// Convert the array to data.
	var data: Data { Data(self) }
}


extension CGImage {
	static let empty = NSImage(size: CGSize(widthHeight: 1), flipped: false) { _ in true }
		.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}


extension CGImage {
	var size: CGSize { CGSize(width: width, height: height) }

	var hasAlphaChannel: Bool {
		switch alphaInfo {
		case .first, .last, .premultipliedFirst, .premultipliedLast:
			return true
		default:
			return false
		}
	}
}


extension CGImage {
	/**
	A read-only pointer to the bytes of the image.

	- Important: Don't assume the format of the underlaying storage. It could be `ARGB`, but it could also be `RGBA`. Draw the image into a `CGContext` first to be safe. See `CGImage#converting`.
	*/
	var bytePointer: UnsafePointer<UInt8>? {
		guard let data = dataProvider?.data else {
			return nil
		}

		return CFDataGetBytePtr(data)
	}

	/**
	The bytes of the image.

	- Important: Don't assume the format of the underlaying storage. It could be `ARGB`, but it could also be `RGBA`. Draw the image into a `CGContext` first to be safe. See `CGImage#converting`.
	*/
	var bytes: [UInt8]? { // swiftlint:disable:this discouraged_optional_collection
		guard let data = dataProvider?.data else {
			return nil
		}

		return (data as Data).bytes
	}
}


extension CGContext {
	/**
	Create a premultiplied RGB bitmap context.

	- Note: `CGContext` does not support non-premultiplied RGB.
	*/
	static func rgbBitmapContext(
		pixelFormat: CGImage.PixelFormat,
		width: Int,
		height: Int,
		withAlpha: Bool
	) -> CGContext? {
		let byteOrder: CGBitmapInfo
		let alphaInfo: CGImageAlphaInfo
		switch pixelFormat {
		case .argb:
			byteOrder = .byteOrder32Big
			alphaInfo = withAlpha ? .premultipliedFirst : .noneSkipFirst
		case .rgba:
			byteOrder = .byteOrder32Big
			alphaInfo = withAlpha ? .premultipliedLast : .noneSkipLast
		case .abgr:
			byteOrder = .byteOrder32Little
			alphaInfo = withAlpha ? .premultipliedFirst : .noneSkipFirst
		case .bgra:
			byteOrder = .byteOrder32Little
			alphaInfo = withAlpha ? .premultipliedLast : .noneSkipLast
		}

		return CGContext(
			data: nil,
			width: width,
			height: height,
			bitsPerComponent: 8,
			bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: byteOrder.rawValue | alphaInfo.rawValue
		)
	}
}


extension vImage_Buffer {
	/// The bytes of the image.
	var bytes: [UInt8] {
		data?.toArray(to: UInt8.self, capacity: rowBytes * Int(height)) ?? []
	}
}


extension CGImage {
	/**
	Convert an image to a `vImage` buffer of the given pixel format.

	- Parameter premultiplyAlpha: Whether the alpha channel should be premultiplied.
	*/
	@available(macOS 11, *)
	func toVImageBuffer(
		pixelFormat: PixelFormat,
		premultiplyAlpha: Bool
	) throws -> vImage_Buffer {
		guard let sourceFormat = vImage_CGImageFormat(cgImage: self) else {
			throw NSError.appError("Could not initialize vImage_CGImageFormat")
		}

		let alphaFirst = premultiplyAlpha ? CGImageAlphaInfo.premultipliedFirst : .first
		let alphaLast = premultiplyAlpha ? CGImageAlphaInfo.premultipliedLast : .last

		let byteOrder: CGBitmapInfo
		let alphaInfo: CGImageAlphaInfo
		switch pixelFormat {
		case .argb:
			byteOrder = .byteOrder32Big
			alphaInfo = alphaFirst
		case .rgba:
			byteOrder = .byteOrder32Big
			alphaInfo = alphaLast
		case .abgr:
			byteOrder = .byteOrder32Little
			alphaInfo = alphaFirst
		case .bgra:
			byteOrder = .byteOrder32Little
			alphaInfo = alphaLast
		}

		guard
			let destinationFormat = vImage_CGImageFormat(
				bitsPerComponent: 8,
				bitsPerPixel: 8 * 4,
				colorSpace: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGBitmapInfo(rawValue: byteOrder.rawValue | alphaInfo.rawValue),
				renderingIntent: .defaultIntent
			)
		else {
			// TODO: Use a proper error.
			throw NSError.appError("Could not initialize vImage_CGImageFormat")
		}

		let converter = try vImageConverter.make(
			sourceFormat: sourceFormat,
			destinationFormat: destinationFormat
		)

		let sourceBuffer = try vImage_Buffer(cgImage: self, format: sourceFormat)

		defer {
			sourceBuffer.free()
		}

		var destinationBuffer = try vImage_Buffer(size: sourceBuffer.size, bitsPerPixel: destinationFormat.bitsPerPixel)

		try converter.convert(source: sourceBuffer, destination: &destinationBuffer)

		return destinationBuffer
	}
}


extension CGImage {
	/**
	Convert the image to use the given underlying pixel format.

	Prefer `CGImage#pixels(…)` if you need to read the pixels of an image. It's faster and also suppot non-premultiplied alpha.

	- Note: The byte pointer uses premultiplied alpha.

	```
	let image = result.image.converting(to: .argb)
	let bytePointer = image.bytePointer
	let bytesPerRow = image.bytesPerRow
	```
	*/
	func converting(to pixelFormat: PixelFormat) -> CGImage? {
		guard
			let context = CGContext.rgbBitmapContext(
				pixelFormat: pixelFormat,
				width: width,
				height: height,
				withAlpha: hasAlphaChannel
			)
		else {
			return nil
		}

		context.draw(self, in: CGRect(origin: .zero, size: size))

		return context.makeImage()
	}
}


extension CGImage {
	enum PixelFormat {
		/// Big-endian, alpha first.
		case argb

		/// Big-endian, alpha last.
		case rgba

		/// Little-endian, alpha first.
		case abgr

		/// Little-endian, alpha last.
		case bgra

		var title: String {
			switch self {
			case .argb:
				return "ARGB"
			case .rgba:
				return "RGBA"
			case .abgr:
				return "ABGR"
			case .bgra:
				return "BGRA"
			}
		}
	}
}

extension CGImage.PixelFormat: CustomDebugStringConvertible {
	var debugDescription: String { "CGImage.PixelFormat(\(title)" }
}


extension CGImage {
	struct Pixels {
		let bytes: [UInt8]
		let width: Int
		let height: Int
		let bytesPerRow: Int
	}

	/**
	Get the pixels of an image.

	- Parameter premultiplyAlpha: Whether the alpha channel should be premultiplied.

	If you pass the pixels to a C API or external library, you most likely want `premultiplyAlpha: false`.
	*/
	func pixels(
		as pixelFormat: PixelFormat,
		premultiplyAlpha: Bool
	) throws -> Pixels {
		// For macOS 10.15 and older, we don't handle the `premultiplyAlpha` option as it never correctly worked before and I'm too lazy to fix it there.
		guard #available(macOS 11, *) else {
			guard
				let image = converting(to: pixelFormat),
				let bytes = image.bytes
			else {
				throw NSError.appError("Could not get the pixels of the image.")
			}

			return Pixels(
				bytes: bytes,
				width: image.width,
				height: image.height,
				bytesPerRow: image.bytesPerRow
			)
		}

		let buffer = try toVImageBuffer(pixelFormat: pixelFormat, premultiplyAlpha: premultiplyAlpha)

		defer {
			buffer.free()
		}

		return Pixels(
			bytes: buffer.bytes,
			width: Int(buffer.width),
			height: Int(buffer.height),
			bytesPerRow: buffer.rowBytes
		)
	}
}


extension CGBitmapInfo {
	/// The alpha info of the current `CGBitmapInfo`.
	var alphaInfo: CGImageAlphaInfo {
		get {
			CGImageAlphaInfo(rawValue: rawValue & Self.alphaInfoMask.rawValue) ?? .none
		}
		set {
			remove(.alphaInfoMask)
			insert(.init(rawValue: newValue.rawValue))
		}
	}

	/// The pixel format of the image.
	/// Returns `nil` if the pixel format is not supported, for example, non-alpha.
	var pixelFormat: CGImage.PixelFormat? {
		// While the host byte order is little-endian, by default, `CGImage` is stored in big-endian format on Intel Macs and little-endian on Apple silicon Macs.

		let alphaInfo = alphaInfo
		let isLittleEndian = contains(.byteOrder32Little)

		guard alphaInfo != .none else {
			// TODO: Support non-alpha formats.
			// return isLittleEndian ? .bgr : .rgb
			return nil
		}

		let isAlphaFirst = alphaInfo == .premultipliedFirst || alphaInfo == .first || alphaInfo == .noneSkipFirst

		if isLittleEndian {
			return isAlphaFirst ? .bgra : .abgr
		} else {
			return isAlphaFirst ? .argb : .rgba
		}
	}

	/// Whether the alpha channel is premultipled.
	var isPremultipliedAlpha: Bool {
		let alphaInfo = alphaInfo
		return alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
	}
}


extension CGColorSpace {
	/// Presentable title of the color space.
	var title: String {
		guard let name = name else {
			return "Unknown"
		}

		return (name as String).replacingOccurrences(of: #"^kCGColorSpace"#, with: "", options: .regularExpression, range: nil)
	}
}


extension CGImage {
	/**
	Debug info for the image.

	```
	print(image.debugInfo)
	```
	*/
	var debugInfo: String {
		"""
		## CGImage debug info ##
		Dimension: \(size.formatted)
		Pixel format: \(bitmapInfo.pixelFormat?.title, default: "Unknown")
		Premultiplied alpha: \(bitmapInfo.isPremultipliedAlpha)
		Color space: \(colorSpace?.title, default: "nil")
		"""
	}
}


@propertyWrapper
struct Clamping<Value: Comparable> {
	private var value: Value
	private let range: ClosedRange<Value>

	init(wrappedValue: Value, _ range: ClosedRange<Value>) {
		self.value = wrappedValue.clamped(to: range)
		self.range = range
	}

	var wrappedValue: Value {
		get { value }
		set {
			value = newValue.clamped(to: range)
		}
	}
}


extension Font {
	/// The default system font size.
	static let systemFontSize = NSFont.systemFontSize.double

	/// The system font in default size.
	static func system(
		weight: Font.Weight = .regular,
		design: Font.Design = .default
	) -> Self {
		system(size: systemFontSize.cgFloat, weight: weight, design: design)
	}
}

extension Font {
	/// The default small system font size.
	static let smallSystemFontSize = NSFont.smallSystemFontSize.double

	/// The system font in small size.
	static func smallSystem(
		weight: Font.Weight = .regular,
		design: Font.Design = .default
	) -> Self {
		system(size: smallSystemFontSize.cgFloat, weight: weight, design: design)
	}
}
