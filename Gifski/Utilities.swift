import SwiftUI
import AVKit
import Combine
import AVFoundation
import Accelerate.vImage
import AppIntents
import Defaults
import Sentry
import ExtendedAttributes

typealias Defaults = _Defaults
typealias Default = _Default
typealias AnyCancellable = Combine.AnyCancellable


// TODO: Check if any of these can be removed when targeting macOS 15.
extension NSItemProvider: @retroactive @unchecked Sendable {}


@discardableResult
func with<T, E>(_ item: T, update: (inout T) throws(E) -> Void) throws(E) -> T {
	var this = item
	try update(&this)
	return this
}


func delay(@_implicitSelfCapture _ duration: Duration, closure: @escaping () -> Void) {
	DispatchQueue.main.asyncAfter(duration, execute: closure)
}


extension DispatchQueue {
	func asyncAfter(_ duration: Duration, execute: @escaping () -> Void) {
		asyncAfter(deadline: .now() + duration.toTimeInterval, execute: execute)
	}

	func asyncAfter(_ duration: Duration, execute: DispatchWorkItem) {
		asyncAfter(deadline: .now() + duration.toTimeInterval, execute: execute)
	}
}


func asyncNilCoalescing<T>(
	_ optional: T?,
	default defaultValue: @escaping @autoclosure () async throws -> T
) async rethrows -> T {
	guard let optional else {
		return try await defaultValue()
	}

	return optional
}

func asyncNilCoalescing<T>(
	_ optional: T?,
	default defaultValue: @escaping @autoclosure () async throws -> T?
) async rethrows -> T? {
	guard let optional else {
		return try await defaultValue()
	}

	return optional
}


// swiftlint:disable:next no_cgfloat
extension CGFloat {
	/**
	Get a Double from a CGFloat. This makes it easier to work with optionals.
	*/
	var toDouble: Double { Double(self) }
}

extension Double {
	/**
	Discouraged but sometimes needed when implicit coercion doesn't work.
	*/
	var toCGFloat: CGFloat { CGFloat(self) } // swiftlint:disable:this no_cgfloat no_cgfloat2

	/**
	If this represents an aspect ratio, return the normalized aspect ratio for each side as a `CGSize`.
	*/
	var normalizedAspectRatioSides: CGSize {
		self > 1.0 ? .init(width: 1.0, height: 1.0 / self) : .init(width: self, height: 1.0)
	}
}

extension BinaryInteger {
	var toDouble: Double { Double(Int(self)) }
}

extension BinaryFloatingPoint {
	var toInt: Int? { self >= Self(Int.min) && self <= Self(Int.max) ? Int(self) : nil }

	var toIntAndClampingIfNeeded: Int { Int(clamped(to: Self(Int.min)...Self(Int.max))) }
}


extension Link<Label<Text, Image>> {
	init(
		_ title: String,
		systemImage: String,
		destination: URL
	) {
		self.init(destination: destination) {
			Label(title, systemImage: systemImage)
		}
	}
}


extension NSView {
	func shake(duration: Duration = .seconds(0.3), direction: NSUserInterfaceLayoutOrientation) {
		let translation = direction == .horizontal ? "x" : "y"
		let animation = CAKeyframeAnimation(keyPath: "transform.translation.\(translation)")
		animation.timingFunction = .linear
		animation.duration = duration.toTimeInterval
		animation.values = [-5, 5, -2.5, 2.5, 0]
		layer?.add(animation, forKey: nil)
	}
}


struct SendFeedbackButton: View {
	var body: some View {
		Link(
			"Feedback & Support",
			systemImage: "exclamationmark.bubble",
			destination: SSApp.appFeedbackUrl()
		)
	}
}


struct ShareAppButton: View {
	let appStoreID: String

	var body: some View {
		ShareLink("Share App", item: "https://apps.apple.com/app/id\(appStoreID)")
	}
}


struct RateOnAppStoreButton: View {
	let appStoreID: String

	var body: some View {
		Link(
			"Rate App",
			systemImage: "star",
			destination: URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)?action=write-review")!
		)
	}
}


// NOTE: This is moot with macOS 12, but `.values` property provided is super buggy and crashes a lot.
extension Publisher where Failure == Never {
	var toAsyncSequence: some AsyncSequence<Output, Failure> {
		AsyncStream(Output.self) { continuation in
			let cancellable = sink { completion in
				switch completion {
				case .finished:
					continuation.finish()
				}
			} receiveValue: { output in
				continuation.yield(output)
			}

			continuation.onTermination = { [cancellable] _ in
				cancellable.cancel()
			}
		}
	}
}


extension Task {
	/**
	Make a task cancellable.

	- Important: You need to assign it to a cancellable property for it to be cancelled. It's not weak by default like Combine.
	*/
	var toCancellable: AnyCancellable { .init(cancel) }
}


extension Sequence {
	func asyncMap<T, E>(
		_ transform: (Element) async throws(E) -> T
	) async throws(E) -> [T] {
		var values = [T]()

		for element in self {
			try await values.append(transform(element))
		}

		return values
	}
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

		if let appearanceName {
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


extension Binding<Double> {
	var doubleToInt: Binding<Int> {
		map(
			get: { Int($0) },
			set: { Double($0) }
		)
	}
}

extension Binding<Int> {
	var intToDouble: Binding<Double> {
		map(
			get: { Double($0) },
			set: { Int($0) }
		)
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
	/**
	Show an alert as a window-modal sheet, or as an app-modal (window-indepedendent) alert if the window is `nil` or not given.
	*/
	@discardableResult
	static func showModal(
		for window: NSWindow? = nil,
		title: String,
		message: String? = nil,
		detailText: String? = nil,
		style: Style = .warning,
		buttonTitles: [String] = [],
		defaultButtonIndex: Int? = nil,
		minimumWidth: Double? = nil
	) -> NSApplication.ModalResponse {
		NSAlert(
			title: title,
			message: message,
			detailText: detailText,
			style: style,
			buttonTitles: buttonTitles,
			defaultButtonIndex: defaultButtonIndex,
			minimumWidth: minimumWidth
		).runModal(for: window)
	}

	/**
	The index in the `buttonTitles` array for the button to use as default.

	Set `-1` to not have any default. Useful for really destructive actions.
	*/
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
		defaultButtonIndex: Int? = nil,
		minimumWidth: Double? = nil
	) {
		self.init()
		self.messageText = title
		self.alertStyle = style

		if let message {
			self.informativeText = message
		}

		if let detailText {
			let scrollView = NSTextView.scrollableTextView()

			// We're setting the frame manually here as it's impossible to use auto-layout,
			// since it has nothing to constrain to. This will eventually be rewritten in SwiftUI anyway.
			scrollView.frame = CGRect(width: minimumWidth ?? 300, height: 120)

			if minimumWidth == nil {
				scrollView.onAddedToSuperview {
					if let messageTextField = (scrollView.superview?.superview?.subviews.first { $0 is NSTextField }) {
						scrollView.frame.width = messageTextField.frame.width
					} else {
						assertionFailure("Couldn't detect the message textfield view of the NSAlert panel")
					}
				}
			}

			let textView = scrollView.documentView as! NSTextView
			textView.drawsBackground = false
			textView.isEditable = false
			textView.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
			textView.textColor = .secondaryLabelColor
			textView.string = detailText

			self.accessoryView = scrollView
		} else if let minimumWidth {
			self.accessoryView = NSView(frame: CGRect(width: minimumWidth, height: 0))
		}

		addButtons(withTitles: buttonTitles)

		if let defaultButtonIndex {
			self.defaultButtonIndex = defaultButtonIndex
		}
	}

	/**
	Runs the alert as a window-modal sheet, or as an app-modal (window-indepedendent) alert if the window is `nil` or not given.
	*/
	@discardableResult
	func runModal(for window: NSWindow? = nil) -> NSApplication.ModalResponse {
		guard let window else {
			return runModal()
		}

		beginSheetModal(for: window) { returnCode in
			NSApp.stopModal(withCode: returnCode)
		}

		return NSApp.runModal(for: window)
	}

	/**
	Adds buttons with the given titles to the alert.
	*/
	func addButtons(withTitles buttonTitles: [String]) {
		for buttonTitle in buttonTitles {
			addButton(withTitle: buttonTitle)
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


extension CMTime {
	/**
	Zero in the video timescale.
	*/
	static var videoZero: Self {
		.init(seconds: 0, preferredTimescale: .video)
	}
}


extension Comparable {
	func clamped(from lowerBound: Self, to upperBound: Self) -> Self {
		min(max(self, lowerBound), upperBound)
	}

	func clamped(to range: ClosedRange<Self>) -> Self {
		clamped(from: range.lowerBound, to: range.upperBound)
	}

	func clamped(to range: PartialRangeThrough<Self>) -> Self {
		min(self, range.upperBound)
	}

	func clamped(to range: PartialRangeFrom<Self>) -> Self {
		max(self, range.lowerBound)
	}
}

extension Strideable where Stride: SignedInteger {
	func clamped(to range: CountableRange<Self>) -> Self {
		clamped(from: range.lowerBound, to: range.upperBound.advanced(by: -1))
	}

	func clamped(to range: CountableClosedRange<Self>) -> Self {
		clamped(from: range.lowerBound, to: range.upperBound)
	}

	func clamped(to range: PartialRangeUpTo<Self>) -> Self {
		min(self, range.upperBound.advanced(by: -1))
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
		if let value {
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
		if let value {
			appendInterpolation(value)
		} else {
			appendLiteral("nil")
		}
	}
}

extension CGSize {
	/**
	Example: `140×100`
	*/
	var formatted: String { "\(Double(width).formatted(.number.grouping(.never)))\u{2009}×\u{2009}\(Double(height).formatted(.number.grouping(.never)))" }
}


extension NSImage {
	/**
	`UIImage` polyfill.
	*/
	convenience init(cgImage: CGImage) {
		self.init(cgImage: cgImage, size: .zero)
	}
}


extension CGImage {
	var toNSImage: NSImage { NSImage(cgImage: self) }
}


extension AVAsset {
	func image(at time: CMTime) async throws -> CGImage? {
		let imageGenerator = AVAssetImageGenerator(asset: self)
		imageGenerator.appliesPreferredTrackTransform = true
		imageGenerator.requestedTimeToleranceAfter = .zero
		imageGenerator.requestedTimeToleranceBefore = .zero
		return try await imageGenerator.image(at: time).image
	}
}


extension AVAssetTrack {
	enum VideoTrimmingError: Error {
		case unknownAssetReaderFailure
		case videoTrackIsEmpty
		case assetIsMissingVideoTrack
		case compositionCouldNotBeCreated
		case codecNotSupported
	}

	/**
	Removes blank frames from the beginning of the track.

	This can be useful to trim blank frames from files produced by tools like the iOS simulator screen recorder.
	*/
	func trimmingBlankFrames() async throws -> AVAssetTrack {
		// See https://github.com/sindresorhus/Gifski/issues/254 for context.
		// In short: Some codecs seem to always report a sample buffer size of 0 when reading, breaking this function. (macOS 11.6)
		let buggyCodecs = ["v210", "BGRA"]
		if
			let codecIdentifier = try await codecIdentifier,
			buggyCodecs.contains(codecIdentifier)
		{
			throw VideoTrimmingError.codecNotSupported
		}

		// Create new composition
		let composition = AVMutableComposition()
		guard
			let wrappedTrack = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: .zero)
		else {
			throw VideoTrimmingError.compositionCouldNotBeCreated
		}

		let (preferredTransform, timeRange) = try await load(.preferredTransform, .timeRange)

		wrappedTrack.preferredTransform = preferredTransform

		try wrappedTrack.insertTimeRange(timeRange, of: self, at: .zero)

		let reader = try AVAssetReader(asset: composition)

		// Create reader for wrapped track.
		let readerOutput = AVAssetReaderTrackOutput(track: wrappedTrack, outputSettings: nil)
		readerOutput.alwaysCopiesSampleData = false

		reader.add(readerOutput)
		reader.startReading()

		defer {
			reader.cancelReading()
		}

		// TODO: When targeting macOS 13, use this instead: https://developer.apple.com/documentation/avfoundation/avsamplebuffergenerator/3950878-makebatch?changes=latest_minor

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
			"Asset could not be read."
		case .videoTrackIsEmpty:
			"Video track is empty."
		case .assetIsMissingVideoTrack:
			"Asset is missing video track."
		case .compositionCouldNotBeCreated:
			"Composition could not be created."
		case .codecNotSupported:
			"Video codec is not supported."
		}
	}
}


extension AVAsset {
	typealias VideoTrimmingError = AVAssetTrack.VideoTrimmingError

	/**
	Removes blank frames from the beginning of the first video track of the asset. The returned asset only includes the first video track.

	This can be useful to trim blank frames from files produced by tools like the iOS simulator screen recorder.
	*/
	func trimmingBlankFramesFromFirstVideoTrack() async throws -> AVAsset {
		guard let firstVideoTrack = try await firstVideoTrack else {
			throw VideoTrimmingError.assetIsMissingVideoTrack
		}

		let trimmedTrack = try await firstVideoTrack.trimmingBlankFrames()

		guard let trimmedAsset = trimmedTrack.asset else {
			assertionFailure("Track is somehow missing asset")
			return AVMutableComposition()
		}

		return trimmedAsset
	}
}


extension AVAssetTrack {
	/**
	Returns the dimensions of the track if it's a video.
	*/
	var dimensions: CGSize? {
		get async throws {
			let (naturalSize, preferredTransform) = try await load(.naturalSize, .preferredTransform)

			guard naturalSize != .zero else {
				return nil
			}

			let size = naturalSize.applying(preferredTransform)
			let preferredSize = CGSize(width: abs(size.width), height: abs(size.height))

			// Workaround for https://github.com/sindresorhus/gifski-app/issues/76
			guard preferredSize != .zero else {
				// SInce this is just a fallback, we don't want to throw the error here.
				return try? await asset?.image(at: CMTime(seconds: 0, preferredTimescale: .video))?.size
			}

			return preferredSize
		}
	}

	/**
	Returns the frame rate of the track if it's a video.
	*/
	var frameRate: Double? {
		get async throws {
			Double(try await load(.nominalFrameRate))
		}
	}

	/**
	Returns the aspect ratio of the track if it's a video.
	*/
	var aspectRatio: Double? {
		get async throws {
			try await dimensions?.aspectRatio
		}
	}

	// TODO: Deprecate this. The system now provides strongly-typed identifiers.
	/**
	Example:
	`avc1` (video)
	`aac` (audio)
	*/
	var codecIdentifier: String? {
		get async throws {
			try await load(.formatDescriptions).first?.mediaSubType.rawValue.fourCharCodeToString().nilIfEmpty
		}
	}

	// TODO: Rename to `format`?
	var codec: AVFormat? {
		get async throws {
			guard let codecString = try await codecIdentifier else {
				return nil
			}

			return AVFormat(fourCC: codecString)
		}
	}

	/**
	Use this for presenting the codec to the user. This is either the codec name, if known, or the codec identifier. You can just default to `"Unknown"` if this is `nil`.
	*/
	var codecTitle: String? {
		get async throws {
			// TODO: Doesn't work because of missing `reasync`.
			// try await codec?.description ?? codecIdentifier

			guard let codec = try await codec else {
				return try await codecIdentifier
			}

			return codec.description
		}
	}

	/**
	Returns a debug string with the media format.

	Example: `vide/avc1`
	*/
	var mediaFormat: String {
		get async throws {
			try await load(.formatDescriptions).map {
				// Get string representation of media type (vide, soun, sbtl, etc.)
				let type = $0.mediaType.description

				// Get string representation media subtype (avc1, aac, tx3g, etc.)
				let subType = $0.mediaSubType.description

				return "\(type)/\(subType)"
			}
				.joined(separator: ",")
		}
	}

	/**
	Estimated file size of the track, in bytes
	*/
	var estimatedFileSize: Int {
		get async throws {
			let (estimatedDataRate, timeRange) = try await load(.estimatedDataRate, .timeRange)
			let dataRateInBytes = Double(estimatedDataRate / 8)
			let bytes = timeRange.duration.seconds * dataRateInBytes
			return Int(bytes)
		}
	}
}


extension AVAssetTrack {
	/**
	Whether the track's duration is the same as the total asset duration.
	*/
	var isFullDuration: Bool {
		get async throws {
			guard let asset else {
				return false
			}

			async let timeRange = load(.timeRange)
			async let assetDuration = asset.load(.duration)

			return try await (timeRange.duration == assetDuration)
		}
	}

	/**
	Extract the track into a new AVAsset.

	Optionally, mutate the track.

	This can be useful if you only want the video or audio of an asset. For example, sometimes the video track duration is shorter than the total asset duration. Extracting the track into a new asset ensures the asset duration is only as long as the video track duration.
	*/
	func extractToNewAsset(
		_ modify: ((AVMutableCompositionTrack) -> Void)? = nil
	) async throws -> AVAsset? {
		let composition = AVMutableComposition()
		let (timeRange, preferredTransform) = try await load(.timeRange, .preferredTransform)

		guard
			let track = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid),
			(try? track.insertTimeRange(CMTimeRange(start: .zero, duration: timeRange.duration), of: self, at: .zero)) != nil
		else {
			return nil
		}

		track.preferredTransform = preferredTransform

		modify?(track)

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
			let asset,
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
	/**
	Create a String representation of a FourCC.
	*/
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
			"hvc1"
		case .h264:
			"avc1"
		case .av1:
			"av01"
		case .vp9:
			"vp09"
		case .appleProResRAWHQ:
			"aprh"
		case .appleProResRAW:
			"aprn"
		case .appleProRes4444XQ:
			"ap4x"
		case .appleProRes4444:
			"ap4h"
		case .appleProRes422HQ:
			"apcn"
		case .appleProRes422:
			"apch"
		case .appleProRes422LT:
			"apcs"
		case .appleProRes422Proxy:
			"apco"
		case .appleAnimation:
			"rle "
		case .hap1:
			"Hap1"
		case .hap5:
			"Hap5"
		case .hapY:
			"HapY"
		case .hapM:
			"HapM"
		case .hapA:
			"HapA"
		case .hap7:
			"Hap7"
		case .cineFormHD:
			"CFHD"
		case .quickTimeGraphics:
			"smc"
		case .avidDNxHD:
			"AVdh"
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

	/**
	- Important: This check only covers known (by us) compatible formats. It might be missing some. Don't use it for strict matching. Also keep in mind that even though a codec is supported, it might still not be decodable as the codec profile level might not be supported.
	*/
	var isSupported: Bool {
		self == .hevc || self == .h264 || isAppleProRes
	}
}

extension AVFormat: CustomStringConvertible {
	var description: String {
		switch self {
		case .hevc:
			"HEVC"
		case .h264:
			"H264"
		case .av1:
			"AV1"
		case .vp9:
			"VP9"
		case .appleProResRAWHQ:
			"Apple ProRes RAW HQ"
		case .appleProResRAW:
			"Apple ProRes RAW"
		case .appleProRes4444XQ:
			"Apple ProRes 4444 XQ"
		case .appleProRes4444:
			"Apple ProRes 4444"
		case .appleProRes422HQ:
			"Apple ProRes 422 HQ"
		case .appleProRes422:
			"Apple ProRes 422"
		case .appleProRes422LT:
			"Apple ProRes 422 LT"
		case .appleProRes422Proxy:
			"Apple ProRes 422 Proxy"
		case .appleAnimation:
			"Apple Animation"
		case .hap1:
			"Vidvox Hap"
		case .hap5:
			"Vidvox Hap Alpha"
		case .hapY:
			"Vidvox Hap Q"
		case .hapM:
			"Vidvox Hap Q Alpha"
		case .hapA:
			"Vidvox Hap Alpha-Only"
		case .hap7:
			// No official name for this.
			"Vidvox Hap"
		case .cineFormHD:
			"CineForm HD"
		case .quickTimeGraphics:
			"QuickTime Graphics"
		case .avidDNxHD:
			"Avid DNxHD"
		}
	}
}

extension AVFormat: CustomDebugStringConvertible {
	var debugDescription: String {
		"\(description) (\(fourCC.trimmingCharacters(in: .whitespaces)))"
	}
}


extension AVMediaType: @retroactive CustomDebugStringConvertible {
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
	/**
	Whether the first video track is decodable.
	*/
	var isVideoDecodable: Bool {
		get async throws {
			guard
				try await load(.isReadable),
				let firstVideoTrack = try await firstVideoTrack
			else {
				return false
			}

			return try await firstVideoTrack.load(.isDecodable)
		}
	}

	/**
	Returns a boolean of whether there are any video tracks.
	*/
	var hasVideo: Bool {
		get async throws {
			try await !loadTracks(withMediaType: .video).isEmpty
		}
	}

	/**
	Returns a boolean of whether there are any audio tracks.
	*/
	var hasAudio: Bool {
		get async throws {
			try await !loadTracks(withMediaType: .audio).isEmpty
		}
	}

	/**
	Returns the first video track if any.
	*/
	var firstVideoTrack: AVAssetTrack? {
		get async throws {
			try await loadTracks(withMediaType: .video).first
		}
	}

	/**
	Returns the first audio track if any.
	*/
	var firstAudioTrack: AVAssetTrack? {
		get async throws {
			try await loadTracks(withMediaType: .audio).first
		}
	}

	/**
	Returns the dimensions of the first video track if any.
	*/
	var dimensions: CGSize? {
		get async throws {
			try await firstVideoTrack?.dimensions
		}
	}

	/**
	Returns the frame rate of the first video track if any.
	*/
	var frameRate: Double? {
		get async throws {
			try await firstVideoTrack?.frameRate
		}
	}

	/**
	Returns the aspect ratio of the first video track if any.
	*/
	var aspectRatio: Double? {
		get async throws {
			try await firstVideoTrack?.aspectRatio
		}
	}

	/**
	Returns the video codec of the first video track if any.
	*/
	var videoCodec: AVFormat? {
		get async throws {
			try await firstVideoTrack?.codec
		}
	}

	/**
	Returns the audio codec of the first audio track if any.

	Example: `aac`
	*/
	var audioCodec: String? {
		get async throws {
			try await firstAudioTrack?.codecIdentifier
		}
	}

	/**
	The file size of the asset, in bytes.

	- Note: If self is an `AVAsset` and not an `AVURLAsset`, the file size will just be an estimate.
	*/
	var fileSize: Int {
		get async throws {
			guard let urlAsset = self as? AVURLAsset else {
				// TODO: Use `concurrentMap` when targeting macOS 15.
				return try await load(.tracks)
					.asyncMap { try await $0.estimatedFileSize }
					.sum()
			}

			return urlAsset.url.fileSize
		}
	}

	var fileSizeFormatted: String {
		get async throws {
			try await fileSize.formatted(.byteCount(style: .file))
		}
	}
}


extension AVAsset {
	/**
	Returns debug info for the asset to use in logging and error messages.
	*/
	var debugInfo: String {
		get async throws {
			var output = [String]()

			let durationFormatter = DateComponentsFormatter()
			durationFormatter.unitsStyle = .abbreviated

			let fileExtension = (self as? AVURLAsset)?.url.fileExtension
			async let codec = asyncNilCoalescing(videoCodec?.debugDescription, default: await self.firstVideoTrack?.codecIdentifier) ?? ""
			async let audioCodec = audioCodec
			async let duration = Duration.seconds(load(.duration).seconds).formatted()
			async let dimensions = dimensions?.formatted
			async let frameRate = frameRate?.rounded(toDecimalPlaces: 2).formatted()
			async let fileSizeFormatted = fileSizeFormatted
			async let (isReadable, isPlayable, isExportable, hasProtectedContent) = load(.isReadable, .isPlayable, .isExportable, .hasProtectedContent)

			output.append(
				"""
				## AVAsset debug info ##
				Extension: \(describing: fileExtension)
				Video codec: \(try await codec)
				Audio codec: \(describing: try await audioCodec)
				Duration: \(describing: try await duration)
				Dimension: \(describing: try await dimensions)
				Frame rate: \(describing: try await frameRate)
				File size: \(try await fileSizeFormatted)
				Is readable: \(try await isReadable)
				Is playable: \(try await isPlayable)
				Is exportable: \(try await isExportable)
				Has protected content: \(try await hasProtectedContent)
				"""
			)

			for track in try await load(.tracks) {
				async let codec = track.mediaType == .video ? asyncNilCoalescing(track.codec?.debugDescription, default: try await track.codecIdentifier) : track.codecIdentifier
				async let duration = Duration.seconds(track.load(.timeRange).duration.seconds).formatted()
				async let dimensions = track.dimensions?.formatted
				async let frameRate = track.frameRate?.rounded(toDecimalPlaces: 2).formatted()
				async let (naturalSize, isPlayable, isDecodable) = track.load(.naturalSize, .isPlayable, .isDecodable)

				output.append(
					"""
					Track #\(track.trackID)
					----
					Type: \(track.mediaType.debugDescription)
					Codec: \(describing: try await codec)
					Duration: \(describing: try await duration)
					Dimensions: \(describing: try await dimensions)
					Natural size: \(describing: try await naturalSize)
					Frame rate: \(describing: try await frameRate)
					Is playable: \(try await isPlayable)
					Is decodable: \(try await isDecodable)
					----
					"""
				)
			}

			return output.joined(separator: "\n\n")
		}
	}
}


extension AVAsset {
	struct VideoMetadata: Hashable {
		let dimensions: CGSize
		let duration: Duration
		let frameRate: Double
		let fileSize: Int
	}

	var videoMetadata: VideoMetadata? {
		get async throws {
			async let dimensionsResult = dimensions
			async let frameRateResult = frameRate
			async let fileSizeResult = fileSize
			async let durationResult = load(.duration)

			guard
				let dimensions = try await dimensionsResult,
				let frameRate = try await frameRateResult
			else {
				return nil
			}

			let fileSize = try await fileSizeResult
			let duration = try await durationResult

			return .init(
				dimensions: dimensions,
				duration: .seconds(duration.seconds),
				frameRate: frameRate,
				fileSize: fileSize
			)
		}
	}
}

extension URL {
	var videoMetadata: AVAsset.VideoMetadata? {
		get async throws {
			try await AVURLAsset(url: self).videoMetadata
		}
	}

	var isVideoDecodable: Bool {
		get async throws {
			try await AVURLAsset(url: self).isVideoDecodable
		}
	}
}


extension NSView {
	func constrainEdgesToSuperview(with insets: NSEdgeInsets = .zero) {
		guard let superview else {
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

	func getConstraintConstantFromSuperView(attribute: NSLayoutConstraint.Attribute) -> Double? {
		guard let constant = getConstraintFromSuperview(attribute: attribute)?.constant else {
			return nil
		}

		return Double(constant)
	}

	func getConstraintFromSuperview(attribute: NSLayoutConstraint.Attribute) -> NSLayoutConstraint? {
		guard let superview else {
			return nil
		}

		return superview.constraints.first {
			($0.secondItem as? NSView == self && $0.secondAttribute == attribute) ||
			($0.firstItem as? NSView == self && $0.firstAttribute == attribute)
		}
	}
}


extension NSPasteboard.PasteboardType {
	/**
	The name of the URL if you put a URL on the pasteboard.
	*/
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
		setString(SSApp.idString, forType: .sourceAppBundleIdentifier)
	}
}

extension NSPasteboard {
	/**
	Starts a new pasteboard writing session. Do all pasteboard write operations in the given closure.

	It takes care of calling `NSPasteboard#prepareForNewContents()` for you and also adds a marker for the source app (`NSPasteboard#setSourceApp()`).

	```
	NSPasteboard.general.with {
		$0.setString("Unicorn", forType: .string)
	}
	```
	*/
	func with(_ callback: (NSPasteboard) -> Void) {
		prepareForNewContents()
		callback(self)
		setSourceApp()
	}
}


extension NSPasteboard {
	/**
	Get the file URLs from dragged and dropped files.
	*/
	func fileURLs(contentTypes: [UTType] = []) -> [URL] {
		var options: [ReadingOptionKey: Any] = [
			.urlReadingFileURLsOnly: true
		]

		if !contentTypes.isEmpty {
			options[.urlReadingContentsConformToTypes] = contentTypes.map(\.identifier)
		}

		guard
			// swiftlint:disable:next legacy_objc_type
			let urls = readObjects(forClasses: [NSURL.self], options: options) as? [URL]
		else {
			return []
		}

		return urls
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
			.OBJC_ASSOCIATION_ASSIGN
		case .retainNonatomic:
			.OBJC_ASSOCIATION_RETAIN_NONATOMIC
		case .copyNonatomic:
			.OBJC_ASSOCIATION_COPY_NONATOMIC
		case .retain:
			.OBJC_ASSOCIATION_RETAIN
		case .copy:
			.OBJC_ASSOCIATION_COPY
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


extension AnyCancellable {
	private static var foreverStore = Set<AnyCancellable>()

	func storeForever() {
		store(in: &Self.foreverStore)
	}
}


extension CAMediaTimingFunction {
	static let `default` = CAMediaTimingFunction(name: .default)
	static let linear = CAMediaTimingFunction(name: .linear)
	static let easeIn = CAMediaTimingFunction(name: .easeIn)
	static let easeOut = CAMediaTimingFunction(name: .easeOut)
	static let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
}


extension String {
	/**
	`NSString` has some useful properties that `String` does not.
	*/
	var toNS: NSString { self as NSString } // swiftlint:disable:this legacy_objc_type
}


enum SSApp {
	static let idString = Bundle.main.bundleIdentifier!
	static let name = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as! String
	static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
	static let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as! String
	static let versionWithBuild = "\(version) (\(build))"
}

extension SSApp {
	static let isFirstLaunch: Bool = {
		let key = "SS_hasLaunched"

		if UserDefaults.standard.bool(forKey: key) {
			return false
		}

		UserDefaults.standard.set(true, forKey: key)
		return true
	}()
}

extension SSApp {
	static func setUpExternalEventListeners() {
		DistributedNotificationCenter.default.publisher(for: .init("\(SSApp.idString):openSendFeedback"))
			.sink { _ in
				DispatchQueue.main.async {
					SSApp.appFeedbackUrl().open()
				}
			}
			.storeForever()

		DistributedNotificationCenter.default.publisher(for: .init("\(SSApp.idString):copyDebugInfo"))
			.sink { _ in
				DispatchQueue.main.async {
					NSPasteboard.general.prepareForNewContents()
					NSPasteboard.general.setString(SSApp.debugInfo, forType: .string)
				}
			}
			.storeForever()
	}
}

extension SSApp {
	static var debugInfo: String {
		"""
		\(name) \(versionWithBuild) - \(idString)
		macOS \(Device.osVersion)
		\(Device.hardwareModel)
		\(Device.architecture)
		"""
	}

	/**
	- Note: Call this lazily only when actually needed as otherwise it won't get the live info.
	*/
	static func appFeedbackUrl() -> URL {
		let info: [String: String] = [
			"product": name,
			"metadata": debugInfo
		]

		return URL("https://sindresorhus.com/feedback").settingQueryItems(from: info)
	}
}

extension SSApp {
	@MainActor
	static var swiftUIMainWindow: NSWindow? {
		// It seems like the main window is always the first one.
		NSApp.windows.first { $0.simpleClassName == "AppKitWindow" }
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

extension SSApp {
	/**
	Initialize Sentry.
	*/
	static func initSentry(_ dsn: String) {
		#if !DEBUG && canImport(Sentry)
		SentrySDK.start {
			$0.dsn = dsn
			$0.enableSwizzling = false
			$0.enableAppHangTracking = false // https://github.com/getsentry/sentry-cocoa/issues/2643
		}
		#endif
	}
}

extension SSApp {
	/**
	Report an error to the chosen crash reporting solution.
	*/
	@inlinable
	static func reportError(
		_ error: Error,
		userInfo: [String: Any] = [:],
		file: String = #fileID,
		line: Int = #line
	) {
		guard !(error is CancellationError) else {
			#if DEBUG
			print("[\(file):\(line)] CancellationError:", error)
			#endif
			return
		}

		let userInfo = userInfo
			.appending([
				"file": file,
				"line": line
			])

		let error = NSError.from(
			error: error,
			userInfo: userInfo
		)

		#if DEBUG
		print("[\(file):\(line)] Reporting error:", error)
		#endif

		#if canImport(Sentry)
		SentrySDK.capture(error: error)
		#endif
	}

	/**
	Report an error message to the chosen crash reporting solution.
	*/
	@inlinable
	static func reportError(
		_ message: String,
		userInfo: [String: Any] = [:],
		file: String = #fileID,
		line: Int = #line
	) {
		reportError(
			message.toError,
			userInfo: userInfo,
			file: file,
			line: line
		)
	}
}


struct GeneralError: LocalizedError, CustomNSError {
	// LocalizedError
	let errorDescription: String?
	let recoverySuggestion: String?
	let helpAnchor: String?

	// CustomNSError
	let errorUserInfo: [String: Any]
	// We don't define `errorDomain` as it will generate something like `AppName.GeneralError` by default.

	init(
		_ description: String,
		recoverySuggestion: String? = nil,
		userInfo: [String: Any] = [:],
		url: URL? = nil,
		underlyingErrors: [Error] = [],
		helpAnchor: String? = nil
	) {
		self.errorDescription = description
		self.recoverySuggestion = recoverySuggestion
		self.helpAnchor = helpAnchor

		self.errorUserInfo = {
			var userInfo = userInfo

			if !underlyingErrors.isEmpty {
				userInfo[NSMultipleUnderlyingErrorsKey] = underlyingErrors
			}

			if let url {
				userInfo[NSURLErrorKey] = url
			}

			return userInfo
		}()
	}
}

extension String {
	/**
	Convert a string into an error.
	*/
	var toError: some LocalizedError { GeneralError(self) }
}


extension URL: @retroactive ExpressibleByStringLiteral {
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


extension URL {
	/**
	Convenience for opening URLs.
	*/
	func open() {
		NSWorkspace.shared.open(self)
	}
}

extension String {
	/*
	```
	"https://sindresorhus.com".openURL()
	```
	*/
	func openURL() {
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
		true
		#else
		false
		#endif
	}()

	static let supportedVideoTypes: [UTType] = [
		.mpeg4Movie,
		.quickTimeMovie
	]
}


typealias QueryDictionary = [String: String]


extension CharacterSet {
	/**
	Characters allowed to be unescaped in an URL.

	https://tools.ietf.org/html/rfc3986#section-2.3
	*/
	static let urlUnreservedRFC3986 = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}

/**
This should really not be necessary, but it's at least needed for my `formspree.io` form...

Otherwise is results in "Internal Server Error" after submitting the form.

Relevant: https://www.djackson.org/why-we-do-not-use-urlcomponents/
*/
private func escapeQueryComponent(_ query: String) -> String {
	query.addingPercentEncoding(withAllowedCharacters: .urlUnreservedRFC3986)!
}


extension Dictionary where Key == String {
	/**
	This correctly escapes items. See `escapeQueryComponent`.
	*/
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
	/**
	This correctly escapes items. See `escapeQueryComponent`.
	*/
	init?(string: String, query: QueryDictionary) {
		self.init(string: string)
		self.queryDictionary = query
	}

	/**
	This correctly escapes items. See `escapeQueryComponent`.
	*/
	var queryDictionary: QueryDictionary {
		get {
			queryItems?.toDictionary { ($0.name, $0.value) }.compactValues() ?? [:]
		}
		set {
			// Using `percentEncodedQueryItems` instead of `queryItems` since the query items are already custom-escaped. See `escapeQueryComponent`.
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

	var contentType: UTType? { resourceValue(forKey: .contentTypeKey) }

	/**
	File size in bytes.
	*/
	var fileSize: Int { resourceValue(forKey: .fileSizeKey) ?? 0 }

	var fileSizeFormatted: String {
		fileSize.formatted(.byteCount(style: .file))
	}

	var exists: Bool { FileManager.default.fileExists(atPath: path) }

	var isReadable: Bool { boolResourceValue(forKey: .isReadableKey) }

	var isWritable: Bool { boolResourceValue(forKey: .isWritableKey) }

	var isVolumeReadonly: Bool { boolResourceValue(forKey: .volumeIsReadOnlyKey) }
}


extension URL {
	/**
	Returns the user's real home directory when called in a sandboxed app.
	*/
	static let realHomeDirectory = Self(
		fileURLWithFileSystemRepresentation: getpwuid(getuid())!.pointee.pw_dir!,
		isDirectory: true,
		relativeTo: nil
	)
}


extension URL {
	func relationship(to url: Self) -> FileManager.URLRelationship {
		var relationship = FileManager.URLRelationship.other
		_ = try? FileManager.default.getRelationship(&relationship, ofDirectoryAt: self, toItemAt: url)
		return relationship
	}
}


extension URL {
	/**
	Check whether the URL is inside the home directory.
	*/
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
	/**
	Whether the directory URL is suitable for use as a default directory for a save panel.
	*/
	var canBeDefaultSavePanelDirectory: Bool {
		// We allow if it's inside the home directory on the main volume or on a different writable volume.
		isInsideHomeDirectory || (!isOnMainVolume && !isVolumeReadonly)
	}
}


extension CGSize {
	static func * (lhs: Self, rhs: Double) -> Self {
		.init(width: lhs.width * rhs, height: lhs.height * rhs)
	}

	init(widthHeight: Double) {
		self.init(width: widthHeight, height: widthHeight)
	}

	var cgRect: CGRect { .init(origin: .zero, size: self) }

	var longestSide: Double { max(width, height) }

	var aspectRatio: Double { width / height }

	func aspectFit(to boundingSize: CGSize) -> Self {
		let ratio = min(boundingSize.width / width, boundingSize.height / height)
		return self * ratio
	}

	func aspectFit(to widthHeight: Double) -> Self {
		aspectFit(to: Self(width: widthHeight, height: widthHeight))
	}

	func aspectFill(to boundingSize: CGSize) -> Self {
		let ratio = max(boundingSize.width / width, boundingSize.height / height)
		return self * ratio
	}

	func aspectFill(to widthHeight: Double) -> Self {
		aspectFill(to: Self(width: widthHeight, height: widthHeight))
	}

	/**
	Returns the simplest integer aspect ratio (width, height) for the current size.

	```
	let (widthRatio, heightRatio) = size.integerAspectRatio()
	```
	*/
	func integerAspectRatio() -> (Int, Int) {
		let roundedWidth = Int(width.rounded())
		let roundedHeight = Int(height.rounded())
		let divisor = greatestCommonDivisor(roundedWidth, roundedHeight)
		let widthRatio = roundedWidth / divisor
		let heightRatio = roundedHeight / divisor
		return (widthRatio, heightRatio)
	}
}


extension CGRect {
	init(origin: CGPoint = .zero, width: Double, height: Double) {
		self.init(origin: origin, size: CGSize(width: width, height: height))
	}

	init(widthHeight: Double) {
		self.init()
		self.origin = .zero
		self.size = CGSize(widthHeight: widthHeight)
	}

	var x: Double {
		get { origin.x }
		set {
			origin.x = newValue
		}
	}

	var y: Double {
		get { origin.y }
		set {
			origin.y = newValue
		}
	}

	var width: Double {
		get { size.width }
		set {
			size.width = newValue
		}
	}

	var height: Double {
		get { size.height }
		set {
			size.height = newValue
		}
	}

	// MARK: - Edges

	var left: Double {
		get { x }
		set {
			x = newValue
		}
	}

	var right: Double {
		get { x + width }
		set {
			x = newValue - width
		}
	}

	var top: Double {
		get { y + height }
		set {
			y = newValue - height
		}
	}

	var bottom: Double {
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

	var centerX: Double {
		get { midX }
		set {
			center = CGPoint(x: newValue, y: midY)
		}
	}

	var centerY: Double {
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
			x: ((rect.width - size.width) / 2) + xOffset,
			y: ((rect.height - size.height) / 2) + yOffset,
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
			xOffset: rect.width * xOffsetPercent,
			yOffset: rect.height * yOffsetPercent
		)
	}

	/**
	Returns a `CGRect` with the same center position, but a new size.
	*/
	func centeredRectWith(size: CGSize) -> Self {
		CGRect(
			x: midX - size.width / 2.0,
			y: midY - size.height / 2.0,
			width: size.width,
			height: size.height
		)
	}

	/**
	Returns a Crop Rect of the current Rect given a certain size
	*/
	func toCropRect(forVideoDimensions dimensions: CGSize) -> CropRect {
		.init(
			x: x / dimensions.width,
			y: y / dimensions.height,
			width: width / dimensions.width,
			height: height / dimensions.height
		)
	}
}


extension Error {
	public var isCancelled: Bool {
		do {
			throw self
		} catch is CancellationError, URLError.cancelled, CocoaError.userCancelled {
			return true
		} catch {
			return false
		}
	}
}


extension NSResponder {
	/**
	Presents the error in the given window if it's not nil, otherwise falls back to an app-modal dialog.
	*/
	public func presentError(_ error: Error, modalFor window: NSWindow?) {
		guard let window else {
			presentError(error)
			return
		}

		presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
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
			domain: "\(SSApp.idString) - \(nsError.domain)\(errorName.isEmpty ? "" : ".")\(errorName)",
			code: nsError.code,
			userInfo: userInfo
		)
	}

	/**
	Returns a new error with the user info appended.
	*/
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

		if let recoverySuggestion {
			userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
		}

		return .init(
			domain: domainPostfix.map { "\(SSApp.idString) - \($0)" } ?? SSApp.idString,
			code: 1, // This is what Swift errors end up as.
			userInfo: userInfo
		)
	}
}


extension Dictionary {
	/**
	Adds the elements of the given dictionary to a copy of self and returns that.

	Identical keys in the given dictionary overwrites keys in the copy of self.
	*/
	func appending(_ dictionary: [Key: Value]) -> [Key: Value] {
		var newDictionary = self

		for (key, value) in dictionary {
			newDictionary[key] = value
		}

		return newDictionary
	}
}


extension Sequence where Element: AdditiveArithmetic {
	func sum() -> Element {
		reduce(into: .zero, +=)
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
	func sum<T: AdditiveArithmetic, E>(_ numerator: (Element) throws(E) -> T) throws(E) -> T {
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
		for _ in 0..<decimalPlaces {
			divisor *= 10
		}

		return (self * divisor).rounded(rule) / divisor
	}
}

extension CGSize {
	func rounded(_ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Self {
		Self(width: width.rounded(rule), height: height.rounded(rule))
	}
}


extension Collection {
	/**
	Returns the element at the specified index if it is within bounds, otherwise `nil`.
	*/
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


// swiftlint:disable all
extension FloatingPoint {
	@inlinable
	public func isAlmostEqual(
		to other: Self,
		tolerance: Self = ulpOfOne.squareRoot()
	) -> Bool {
		assert(tolerance >= .ulpOfOne && tolerance < 1, "tolerance should be in [.ulpOfOne, 1).")

		guard isFinite, other.isFinite else {
			return rescaledAlmostEqual(to: other, tolerance: tolerance)
		}

		let scale = max(abs(self), abs(other), .leastNormalMagnitude)
		return abs(self - other) < scale * tolerance
	}

	@inlinable
	public func isAlmostZero(
		absoluteTolerance tolerance: Self = ulpOfOne.squareRoot()
	) -> Bool {
		assert(tolerance > 0)
		return abs(self) < tolerance
	}

	@usableFromInline
	func rescaledAlmostEqual(to other: Self, tolerance: Self) -> Bool {
		if isNaN || other.isNaN {
			return false
		}

		if isInfinite {
			if other.isInfinite {
				return self == other
			}

			let scaledSelf = Self(
				sign: sign,
				exponent: Self.greatestFiniteMagnitude.exponent,
				significand: 1
			)
			let scaledOther = Self(
				sign: .plus,
				exponent: -1,
				significand: other
			)

			return scaledSelf.isAlmostEqual(to: scaledOther, tolerance: tolerance)
		}

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
		self.top = top
		self.left = left
		self.bottom = bottom
		self.right = right
	}

	init(all: Double) {
		self.init(
			top: all,
			left: all,
			bottom: all,
			right: all
		)
	}

	var vertical: Double { top + bottom }
	var horizontal: Double { left + right }
}


extension URL {
	func setAppAsItemCreator() throws {
		try systemMetadata.set(kMDItemCreator as String, value: "\(SSApp.name) \(SSApp.version)")
	}
}


extension URL {
	var components: URLComponents? {
		URLComponents(url: self, resolvingAgainstBaseURL: true)
	}

	var queryDictionary: [String: String] { components?.queryDictionary ?? [:] }
}


extension NSView {
	/**
	Get a subview matching a condition.
	*/
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
	/**
	Returns copy of the constraint with changed properties provided as arguments.
	*/
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
			// The compiler fails to auto-convert to CGFloat here.
			multiplier: multiplier.flatMap(CGFloat.init) ?? self.multiplier,
			constant: constant.flatMap(CGFloat.init) ?? self.constant
		)
	}

	func animate(
		to constant: Double,
		duration: Duration,
		timingFunction: CAMediaTimingFunction = .init(name: .easeInEaseOut),
		completionHandler: (() -> Void)? = nil
	) {
		NSAnimationContext.runAnimationGroup { context in
			context.duration = duration.toTimeInterval
			context.timingFunction = timingFunction
			animator().constant = constant
		} completionHandler: {
			completionHandler?()
		}
	}
}


extension NSObject {
	// Note: It's intentionally a getter to get the dynamic self.
	/**
	Returns the class name without module name.
	*/
	static var simpleClassName: String { String(describing: self) }

	/**
	Returns the class name of the instance without module name.
	*/
	var simpleClassName: String { Self.simpleClassName }
}


extension CMTime {
	/**
	Get the `CMTime` as a duration from zero to the seconds value of `self`.

	Can be `nil` when the `.duration` is not available, for example, when an asset has not yet been fully loaded or if it's a live stream.
	*/
	var durationRange: ClosedRange<Double>? {
		guard isNumeric else {
			return nil
		}

		return 0...seconds
	}
}


extension CMTimeRange {
	/**
	Get `self` as a range in seconds.

	Can be `nil` when the range is not available, for example, when an asset has not yet been fully loaded or if it's a live stream.
	*/
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
	/**
	The duration range of the item.

	Can be `nil` when the `.duration` is not available, for example, when the asset has not yet been fully loaded or if it's a live stream.
	*/
	var durationRange: ClosedRange<Double>? { duration.durationRange }

	/**
	The playable range of the item.

	Can be `nil` when the `.duration` is not available, for example, when the asset has not yet been fully loaded or if it's a live stream. Or if the user is dragging the trim handle of a video.
	*/
	var playbackRange: ClosedRange<Double>? {
		get {
			// These are not available while the user is dragging the video trim handle of `AVPlayerView`.
			guard
				reversePlaybackEndTime.isNumeric,
				forwardPlaybackEndTime.isNumeric
			else {
				return nil
			}

			let startTime = reversePlaybackEndTime.seconds
			let endTime = forwardPlaybackEndTime.seconds

			return .fromGraceful(startTime, endTime)
		}
		set {
			guard let newValue else {
				return
			}

			forwardPlaybackEndTime = CMTime(seconds: newValue.upperBound, preferredTimescale: .video)
			reversePlaybackEndTime = CMTime(seconds: newValue.lowerBound, preferredTimescale: .video)
		}
	}
}


extension FileManager {
	/**
	Copy a file and optionally overwrite the destination if it exists.
	*/
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
	/**
	Get the length between the lower and upper bound.
	*/
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

extension ClosedRange<Double> {
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
	/**
	Present the error as an async sheet on the given window.

	- Note: This exists because the built-in `NSResponder#presentError(forModal:)` method requires too many arguments, selector as callback, and it says it's modal but it's not blocking, which is surprising.
	*/
	func presentAsSheet(for window: NSWindow, didPresent: (() -> Void)?) {
		NSApp.presentErrorAsSheet(self, for: window, didPresent: didPresent)
	}

	/**
	Present the error as a blocking modal sheet on the given window.

	If the window is nil, the error will be presented in an app-level modal dialog.
	*/
	func presentAsModalSheet(for window: NSWindow?) {
		guard let window else {
			presentAsModal()
			return
		}

		presentAsSheet(for: window) {
			NSApp.stopModal()
		}

		NSApp.runModal(for: window)
	}

	/**
	Present the error as a blocking app-level modal dialog.
	*/
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

	/**
	Loop the playback.
	*/
	var loopPlayback = false {
		didSet {
			updateObserver()
		}
	}

	/**
	Bounce the playback.
	*/
	var bouncePlayback = false {
		didSet {
			updateObserver()

			if !bouncePlayback, rate == -1 {
				rate = 1
			}
		}
	}

	override func replaceCurrentItem(with item: AVPlayerItem?) {
		super.replaceCurrentItem(with: item)
		cancellable = nil
		updateObserver()
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
				guard let self else {
					return
				}

				pause()

				if
					bouncePlayback,
					currentItem?.canPlayReverse == true,
					currentTime().seconds > currentItem?.playbackRange?.lowerBound ?? 0
				{
					seekToEnd()
					playImmediately(atRate: -defaultRate)
				} else if loopPlayback {
					seekToStart()
					playImmediately(atRate: defaultRate)
				}
			}
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
			if
				let last = result.last,
				last.count < chunkSize
			{
				result.append(result.removeLast() + [current])
			} else {
				result.append([current])
			}
		}
	}
}


extension Collection where Index == Int {
	/**
	Return a subset of the array of the given length by sampling "evenly distributed" elements.
	*/
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
	private let delay: Duration
	private var workItem: DispatchWorkItem?

	init(delay: Duration) {
		self.delay = delay
	}

	func callAsFunction(_ action: @escaping () -> Void) {
		workItem?.cancel()
		let newWorkItem = DispatchWorkItem(block: action)
		DispatchQueue.main.asyncAfter(delay, execute: newWorkItem)
		workItem = newWorkItem
	}
}

extension Debouncer {
	private static var debouncers = AtomicDictionary<String, Debouncer>()

	private static func debounce(
		identifier: String,
		delay: Duration,
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
		delay: Duration,
		action: @escaping () -> Void
	) {
		let identifier = "\(file)-\(function)-\(line)"
		debounce(identifier: identifier, delay: delay, action: action)
	}
}


extension Sequence where Element: Sequence {
	func flatten() -> [Element.Element] {
		flatMap(\.self)
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
		}

		if count > number {
			return String(prefix(number - truncationIndicator.count)).trimmedTrailing + truncationIndicator
		}

		return self
	}
}


extension CGImage {
	static let empty = NSImage(size: CGSize(widthHeight: 1), flipped: false) { _ in true }
		.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}


extension CGImage {
	var size: CGSize { CGSize(width: width, height: height) }
}


extension CGImage {
	/**
	Convert an image to a `vImage` buffer of the given pixel format.

	- Parameter premultiplyAlpha: Whether the alpha channel should be premultiplied.
	*/
	func toVImageBuffer(
		pixelFormat: PixelFormat,
		premultiplyAlpha: Bool
	) throws -> vImage.PixelBuffer<vImage.Interleaved8x4> {
		guard
			var imageFormat = vImage_CGImageFormat(
				bitsPerComponent: vImage.Interleaved8x4.bitCountPerComponent,
				bitsPerPixel: vImage.Interleaved8x4.bitCountPerPixel,
				colorSpace: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: pixelFormat.toBitmapInfo(premultiplyAlpha: premultiplyAlpha),
				renderingIntent: .perceptual
			)
		else {
			throw NSError.appError("Could not initialize vImage_CGImageFormat")
		}

		return try vImage.PixelBuffer(
			cgImage: self,
			cgImageFormat: &imageFormat,
			pixelFormat: vImage.Interleaved8x4.self
		)
	}
}


extension CGImage {
	enum PixelFormat {
		/**
		Big-endian, alpha first.
		*/
		case argb

		/**
		Big-endian, alpha last.
		*/
		case rgba

		/**
		Little-endian, alpha first.
		*/
		case bgra

		/**
		Little-endian, alpha last.
		*/
		case abgr

		var title: String {
			switch self {
			case .argb:
				"ARGB"
			case .rgba:
				"RGBA"
			case .bgra:
				"BGRA"
			case .abgr:
				"ABGR"
			}
		}
	}
}

extension CGImage.PixelFormat: CustomDebugStringConvertible {
	var debugDescription: String { "CGImage.PixelFormat(\(title)" }
}

extension CGImage.PixelFormat {
	func toBitmapInfo(premultiplyAlpha: Bool) -> CGBitmapInfo {
		let alphaFirst = premultiplyAlpha ? CGImageAlphaInfo.premultipliedFirst : .first
		let alphaLast = premultiplyAlpha ? CGImageAlphaInfo.premultipliedLast : .last

		let byteOrder: CGBitmapInfo
		let alphaInfo: CGImageAlphaInfo
		switch self {
		case .argb:
			byteOrder = .byteOrder32Big
			alphaInfo = alphaFirst
		case .rgba:
			byteOrder = .byteOrder32Big
			alphaInfo = alphaLast
		case .bgra:
			byteOrder = .byteOrder32Little
			alphaInfo = alphaFirst // This might look wrong, but the order is inverse because of little endian.
		case .abgr:
			byteOrder = .byteOrder32Little
			alphaInfo = alphaLast
		}

		return CGBitmapInfo(rawValue: byteOrder.rawValue | alphaInfo.rawValue)
	}
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
		let buffer = try toVImageBuffer(pixelFormat: pixelFormat, premultiplyAlpha: premultiplyAlpha)

		return Pixels(
			bytes: buffer.array,
			width: buffer.width,
			height: buffer.height,
			bytesPerRow: buffer.byteCountPerRow
		)
	}
}


extension vImage.PixelBuffer where Format: StaticPixelFormat {
	var byteCountPerRow: Int { width * byteCountPerPixel }
}


extension CGBitmapInfo {
	/**
	The alpha info of the current `CGBitmapInfo`.
	*/
	var alphaInfo: CGImageAlphaInfo {
		get {
			CGImageAlphaInfo(rawValue: rawValue & Self.alphaInfoMask.rawValue) ?? .none
		}
		set {
			remove(.alphaInfoMask)
			insert(.init(rawValue: newValue.rawValue))
		}
	}

	/**
	The pixel format of the image.

	Returns `nil` if the pixel format is not supported, for example, non-alpha.
	*/
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
		}

		return isAlphaFirst ? .argb : .rgba
	}

	/**
	Whether the alpha channel is premultipled.
	*/
	var isPremultipliedAlpha: Bool {
		let alphaInfo = alphaInfo
		return alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
	}
}


extension CGColorSpace {
	/**
	Presentable title of the color space.
	*/
	var title: String {
		guard let name else {
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


extension Font {
	/**
	The default system font size.
	*/
	static let systemFontSize = NSFont.systemFontSize.toDouble

	/**
	The system font in default size.
	*/
	static func system(
		weight: Font.Weight = .regular,
		design: Font.Design = .default
	) -> Self {
		system(size: systemFontSize, weight: weight, design: design)
	}
}

extension Font {
	/**
	The default small system font size.
	*/
	static let smallSystemFontSize = NSFont.smallSystemFontSize.toDouble

	/**
	The system font in small size.
	*/
	static func smallSystem(
		weight: Font.Weight = .regular,
		design: Font.Design = .default
	) -> Self {
		system(size: smallSystemFontSize, weight: weight, design: design)
	}
}


extension CMTime {
	static func * (lhs: Self, rhs: Double) -> Self {
		CMTimeMultiplyByFloat64(lhs, multiplier: rhs)
	}

	static func *= (lhs: inout Self, rhs: Double) {
		lhs = lhs * rhs
	}

	static func / (lhs: Self, rhs: Double) -> Self {
		lhs * (1.0 / rhs)
	}

	static func /= (lhs: inout Self, rhs: Double) {
		lhs = lhs / rhs
	}
}


extension AVMutableCompositionTrack {
	/**
	Change the speed of the track using the given multiplier.

	1 is the current speed. 2 means doubled speed. Etc.
	*/
	func changeSpeed(by speedMultiplier: Double) {
		scaleTimeRange(timeRange, toDuration: timeRange.duration / speedMultiplier)
	}
}


extension AVAssetTrack {
	/**
	Extract the track to a new asset and also change the speed of the track using the given multiplier.

	1 is the current speed. 2 means doubled speed. Etc.
	*/
	func extractToNewAssetAndChangeSpeed(to speedMultiplier: Double) async throws -> AVAsset? {
		try await extractToNewAsset {
			$0.changeSpeed(by: speedMultiplier)
		}
	}
}


extension AVPlayerItem {
	/**
	The played duration percentage (`0...1`).
	*/
	var playbackProgress: Double {
		let totalDuration = duration.seconds
		let duration = currentTime().seconds

		guard
			totalDuration != 0,
			duration != 0
		else {
			return 0
		}

		return duration / totalDuration
	}

	/**
	Seek to the given percentage (`0...1`) of the total duration.
	*/
	func seek(toPercentage percentage: Double) {
		seek(
			to: duration * percentage,
			toleranceBefore: .zero,
			toleranceAfter: .zero,
			completionHandler: nil
		)
	}
}


extension AVPlayerItem {
	/**
	The playable range of the item as percentage of the total duration.

	For example, if the video has a duration of 10 seconds and you trim it to the last half, this would return `0.5...1`.

	Can be `nil` when the `.duration` is not available, for example, when the asset has not yet been fully loaded or if it's a live stream.
	*/
	var playbackRangePercentage: ClosedRange<Double>? {
		get {
			guard
				let playbackRange,
				let duration = durationRange?.upperBound
			else {
				return nil
			}

			let lowerPercentage = playbackRange.lowerBound / duration
			let upperPercentage = playbackRange.upperBound / duration
			return lowerPercentage...upperPercentage
		}
		set {
			guard
				let duration = durationRange?.upperBound,
				let playbackPercentageRange = newValue
			else {
				return
			}

			let lowerBound = duration * playbackPercentageRange.lowerBound
			let upperBound = duration * playbackPercentageRange.upperBound
			playbackRange = lowerBound...upperBound
		}
	}
}


enum OperatingSystem {
	case macOS
	case iOS
	case tvOS
	case watchOS
	case visionOS

	#if os(macOS)
	static let current = macOS
	#elseif os(iOS)
	static let current = iOS
	#elseif os(tvOS)
	static let current = tvOS
	#elseif os(watchOS)
	static let current = watchOS
	#elseif os(visionOS)
	static let current = visionOS
	#else
	#error("Unsupported platform")
	#endif
}

extension OperatingSystem {
	static let isMacOS = current == .macOS
	static let isIOS = current == .iOS
	static let isVisionOS = current == .visionOS
	static let isMacOrVision = isMacOS || isVisionOS
	static let isIOSOrVision = isIOS || isVisionOS

	static let isMacOS16OrLater: Bool = {
		#if os(macOS)
		if #available(macOS 16, *) {
			return true
		}

		return false
		#else
		false
		#endif
	}()

	static let isMacOS15OrLater: Bool = {
		#if os(macOS)
		if #available(macOS 15, *) {
			return true
		}

		return false
		#else
		false
		#endif
	}()
}

typealias OS = OperatingSystem


extension ClosedRange {
	/**
	Create a `ClosedRange` where it does not matter which bound is upper and lower.

	Using a range literal would hard crash if the lower bound is higher than the upper bound.
	*/
	static func fromGraceful(_ bound1: Bound, _ bound2: Bound) -> Self {
		bound1 <= bound2 ? bound1...bound2 : bound2...bound1
	}
}


extension Duration {
	var nanoseconds: Int64 {
		let (seconds, attoseconds) = components
		let secondsNanos = seconds * 1_000_000_000
		let attosecondsNanons = attoseconds / 1_000_000_000
		let (totalNanos, isOverflow) = secondsNanos.addingReportingOverflow(attosecondsNanons)
		return isOverflow ? .max : totalNanos
	}

	var toTimeInterval: TimeInterval { Double(nanoseconds) / 1_000_000_000 }
}


struct ImportedVideoFile: Transferable {
	let url: URL

	static var transferRepresentation: some TransferRepresentation {
		FileRepresentation.importedURL(
			.mpeg4Movie,
			.quickTimeMovie
		) {
			Self(url: $0)
		}
	}
}


extension FileRepresentation {
	/**
	An importing-only file representation that copies the URL to a temporary directory and returns that.

	```
	struct VideoFile: Transferable {
		let url: URL

		static var transferRepresentation: some TransferRepresentation {
			FileRepresentation.importedURL(contentType: .mpeg4Movie) { Self(url: $0) }
		}
	}
	```
	*/
	static func importedURL(
		_ contentType: UTType,
		createItem: @escaping (URL) async throws -> Item
	) -> Self {
		.init(importedContentType: contentType) {
			try await createItem(try $0.file.copyToUniqueTemporaryDirectory())
		}
	}

	// TODO: Use variadic generics here when targeting macOS 15.
	@TransferRepresentationBuilder<Item>
	static func importedURL(
		_ contentType1: UTType,
		_ contentType2: UTType,
		createItem: @escaping (URL) async throws -> Item
	) -> some TransferRepresentation<Item> {
		importedURL(contentType1, createItem: createItem)
		importedURL(contentType2, createItem: createItem)
	}

	@TransferRepresentationBuilder<Item>
	static func importedURL(
		_ contentType1: UTType,
		_ contentType2: UTType,
		_ contentType3: UTType,
		createItem: @escaping (URL) async throws -> Item
	) -> some TransferRepresentation<Item> {
		importedURL(contentType1, createItem: createItem)
		importedURL(contentType2, createItem: createItem)
		importedURL(contentType3, createItem: createItem)
	}

	@TransferRepresentationBuilder<Item>
	static func importedURL(
		_ contentType1: UTType,
		_ contentType2: UTType,
		_ contentType3: UTType,
		_ contentType4: UTType,
		createItem: @escaping (URL) async throws -> Item
	) -> some TransferRepresentation<Item> {
		importedURL(contentType1, createItem: createItem)
		importedURL(contentType2, createItem: createItem)
		importedURL(contentType3, createItem: createItem)
		importedURL(contentType4, createItem: createItem)
	}
}


extension View {
	/**
	Fills the frame.
	*/
	func fillFrame(
		_ axis: Axis.Set = [.horizontal, .vertical],
		alignment: Alignment = .center
	) -> some View {
		frame(
			maxWidth: axis.contains(.horizontal) ? .infinity : nil,
			maxHeight: axis.contains(.vertical) ? .infinity : nil,
			alignment: alignment
		)
	}
}


// TODO: Try to use `ContainerRelativeShape` when it's supported outside of widgets. (as of macOS 11.2.3, it's only supported in widgets)
// Note: I have extensively tested and researched the current code. Don't change it lightly.
extension View {
	/**
	Corner radius with a custom corner style.
	*/
	func cornerRadius(_ radius: Double, style: RoundedCornerStyle = .continuous) -> some View {
		clipShape(.rect(cornerRadius: radius, style: style))
	}

	/**
	Draws a border inside the view.
	*/
	@_disfavoredOverload
	func border(
		_ content: some ShapeStyle,
		width lineWidth: Double = 1,
		cornerRadius: Double,
		cornerStyle: RoundedCornerStyle = .circular
	) -> some View {
		self.cornerRadius(cornerRadius, style: cornerStyle)
			.overlay {
				RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle)
					.strokeBorder(content, lineWidth: lineWidth)
			}
	}

	// I considered supporting an `inside`/`center` position option, but there's really no benefit to drawing the border at center as we need to pad the view anyway because of the clipping.
	/**
	Draws a border inside the view.
	*/
	func border(
		_ color: Color,
		width lineWidth: Double = 1,
		cornerRadius: Double,
		cornerStyle: RoundedCornerStyle = .circular
	) -> some View {
		self.cornerRadius(cornerRadius, style: cornerStyle)
			.overlay {
				RoundedRectangle(cornerRadius: cornerRadius, style: cornerStyle)
					.strokeBorder(color, lineWidth: lineWidth)
			}
	}
}


// TODO: Remove these when targeting macOS 15.
extension NSItemProvider {
	func loadObject<T>(ofClass: T.Type) async throws -> T? where T: NSItemProviderReading {
		try await withCheckedThrowingContinuation { continuation in
			_ = loadObject(ofClass: ofClass) { data, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard let object = data as? T else {
					continuation.resume(returning: nil)
					return
				}

				continuation.resume(returning: object)
			}
		}
	}

	func loadObject<T>(ofClass: T.Type) async throws -> T? where T: _ObjectiveCBridgeable, T._ObjectiveCType: NSItemProviderReading {
		try await withCheckedThrowingContinuation { continuation in
			_ = loadObject(ofClass: ofClass) { data, error in
				if let error {
					continuation.resume(throwing: error)
					return
				}

				guard let data else {
					continuation.resume(returning: nil)
					return
				}

				continuation.resume(returning: data)
			}
		}
	}
}

extension NSItemProvider {
	/**
	Get a URL from the item provider, if any.
	*/
	func getURL() async -> URL? {
		try? await loadObject(ofClass: URL.self)
	}
}


extension Sequence {
	func asyncFlatMap<T: Sequence, E>(
		_ transform: (Element) async throws(E) -> T
	) async throws(E) -> [T.Element] {
		var values = [T.Element]()

		for element in self {
			try await values.append(contentsOf: transform(element))
		}

		return values
	}
}


extension Sequence where Element: Sendable {
	func concurrentCompactMap<T: Sendable>(
		withPriority priority: TaskPriority? = nil,
		concurrencyLimit: Int? = nil,
		_ transform: @Sendable (Element) async -> T?
	) async -> [T] {
		await chunked(by: concurrencyLimit ?? .max).asyncFlatMap { chunk in
			await withoutActuallyEscaping(transform) { escapingTransform in
				await withTaskGroup(of: (offset: Int, value: T?).self) { group -> [T] in
					for (offset, element) in chunk.enumerated() {
						group.addTask(priority: priority) {
							await (offset, escapingTransform(element))
						}
					}

					var result = [(offset: Int, value: T)]()
					result.reserveCapacity(chunk.count)

					while let next = await group.next() {
						if let value = next.value {
							result.append((offset: next.offset, value: value))
						}
					}

					return result
						.sorted { $0.offset < $1.offset }
						.map(\.value)
				}
			}
		}
	}
}


struct NativeVisualEffectsView: NSViewRepresentable {
	typealias NSViewType = NSVisualEffectView

	var material: NSVisualEffectView.Material
	var blendingMode = NSVisualEffectView.BlendingMode.withinWindow
	var state = NSVisualEffectView.State.followsWindowActiveState
	var isEmphasized = false
	var cornerRadius = 0.0

	func makeNSView(context: Context) -> NSViewType {
		let nsView = NSVisualEffectView()
		nsView.wantsLayer = true
		nsView.translatesAutoresizingMaskIntoConstraints = false
		nsView.setContentHuggingPriority(.defaultHigh, for: .vertical)
		nsView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
		nsView.setAccessibilityHidden(true)
		nsView.layer?.masksToBounds = true
		return nsView
	}

	func updateNSView(_ nsView: NSViewType, context: Context) {
		nsView.material = material
		nsView.blendingMode = blendingMode
		nsView.state = state
		nsView.isEmphasized = isEmphasized
		nsView.layer?.cornerRadius = cornerRadius
	}
}

extension View {
	/**
	Add a material as a background.

	Only use this over the native materials when either:
	- You need to blend with what's behind the window.
	- You need the material to be visible even when the window is inactive.
	*/
	func backgroundWithMaterial(
		_ material: NSVisualEffectView.Material,
		blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
		state: NSVisualEffectView.State = .followsWindowActiveState,
		isEmphasized: Bool = false,
		cornerRadius: Double = 0,
		ignoresSafeAreaEdges edges: Edge.Set = .all
	) -> some View {
		background {
			NativeVisualEffectsView(
				material: material,
				blendingMode: blendingMode,
				state: state,
				isEmphasized: isEmphasized,
				cornerRadius: cornerRadius
			)
				.ignoresSafeArea(edges: edges)
		}
	}
}

extension View {
	/**
	https://twitter.com/oskargroth/status/1323013160333381641
	*/
	func visualEffectsViewVibrancy(_ level: Double) -> some View {
		blendMode(.overlay)
			.overlay {
				opacity(1 - level)
			}
	}
}


extension Binding {
	/**
	Converts the binding of an optional value to a binding to a boolean for whether the value is non-nil.

	You could use this in a `isPresent` parameter for a sheet, alert, etc, to have it show when the value is non-nil.
	*/
	func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
		.init(
			get: { wrappedValue != nil },
			set: { isPresented in
				if !isPresented {
					wrappedValue = nil
				}
			}
		)
	}
}


extension Binding {
	func map<Result>(
		get: @escaping (Value) -> Result,
		set: @escaping (Result) -> Value
	) -> Binding<Result> {
		.init(
			get: { get(wrappedValue) },
			set: { newValue in
				wrappedValue = set(newValue)
			}
		)
	}
}


extension View {
	func alert(error: Binding<Error?>) -> some View {
		alert2(
			title: { ($0 as NSError).localizedDescription },
			message: { ($0 as NSError).localizedRecoverySuggestion },
			presenting: error
		) {
			let nsError = $0 as NSError
			if
				let options = nsError.localizedRecoveryOptions,
				let recoveryAttempter = nsError.recoveryAttempter
			{
				// Alert only supports 3 buttons, so we limit it to 2 attempters, otherwise it would take over the cancel button.
				ForEach(Array(options.prefix(2).enumerated()), id: \.0) { index, option in
					Button(option) {
						// We use the old NSError mechanism for recovery attempt as recoverable NSError's are not bridged to RecoverableError.
						_ = (recoveryAttempter as AnyObject).attemptRecovery(fromError: nsError, optionIndex: index)
					}
				}
				Button("Cancel", role: .cancel) {}
			}
		}
	}
}


extension View {
	/**
	This allows multiple sheets on a single view, which `.sheet()` doesn't.
	*/
	func sheet2(
		isPresented: Binding<Bool>,
		onDismiss: (() -> Void)? = nil,
		@ViewBuilder content: @escaping () -> some View
	) -> some View {
		background(
			EmptyView().sheet(
				isPresented: isPresented,
				onDismiss: onDismiss,
				content: content
			)
		)
	}

	/**
	This allows multiple sheets on a single view, which `.sheet()` doesn't.
	*/
	func sheet2<Item: Identifiable>(
		item: Binding<Item?>,
		onDismiss: (() -> Void)? = nil,
		@ViewBuilder content: @escaping (Item) -> some View
	) -> some View {
		background(
			EmptyView().sheet(
				item: item,
				onDismiss: onDismiss,
				content: content
			)
		)
	}
}


extension View {
	/**
	This allows multiple popovers on a single view, which `.popover()` doesn't.
	*/
	func popover2(
		isPresented: Binding<Bool>,
		attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
		arrowEdge: Edge = .top,
		@ViewBuilder content: @escaping () -> some View
	) -> some View {
		background(
			EmptyView()
				.popover(
					isPresented: isPresented,
					attachmentAnchor: attachmentAnchor,
					arrowEdge: arrowEdge,
					content: content
				)
		)
	}
}



// Multiple `.alert` are stil broken in iOS 15.0
extension View {
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2(
		_ title: Text,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: () -> some View,
		@ViewBuilder message: () -> some View
	) -> some View {
		background(
			EmptyView()
				.alert(
					title,
					isPresented: isPresented,
					actions: actions,
					message: message
				)
		)
	}

	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2(
		_ title: String,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: () -> some View,
		@ViewBuilder message: () -> some View
	) -> some View {
		alert2(
			Text(title),
			isPresented: isPresented,
			actions: actions,
			message: message
		)
	}

	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2(
		_ title: Text,
		message: String? = nil,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: () -> some View
	) -> some View {
		alert2(
			title,
			isPresented: isPresented,
			actions: actions,
			message: { // swiftlint:disable:this trailing_closure
				if let message {
					Text(message)
				}
			}
		)
	}

	// This is a convenience method and does not exist natively.
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2(
		_ title: String,
		message: String? = nil,
		isPresented: Binding<Bool>,
		@ViewBuilder actions: () -> some View
	) -> some View {
		alert2(
			title,
			isPresented: isPresented,
			actions: actions,
			message: { // swiftlint:disable:this trailing_closure
				if let message {
					Text(message)
				}
			}
		)
	}

	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2(
		_ title: Text,
		message: String? = nil,
		isPresented: Binding<Bool>
	) -> some View {
		alert2(
			title,
			message: message,
			isPresented: isPresented,
			actions: {} // swiftlint:disable:this trailing_closure
		)
	}

	// This is a convenience method and does not exist natively.
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2(
		_ title: String,
		message: String? = nil,
		isPresented: Binding<Bool>
	) -> some View {
		alert2(
			title,
			message: message,
			isPresented: isPresented,
			actions: {} // swiftlint:disable:this trailing_closure
		)
	}
}


extension View {
	// This exist as the new `item`-type alert APIs in iOS 15 are shit.
	// This is a convenience method and does not exist natively.
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2<T>(
		title: (T) -> Text,
		presenting data: Binding<T?>,
		@ViewBuilder actions: (T) -> some View,
		@ViewBuilder message: (T) -> some View
	) -> some View {
		background(
			EmptyView()
				.alert(
					data.wrappedValue.map(title) ?? Text(""),
					isPresented: data.isPresent(),
					presenting: data.wrappedValue,
					actions: actions,
					message: message
				)
		)
	}

	// This is a convenience method and does not exist natively.
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2<T>(
		title: (T) -> Text,
		message: ((T) -> String?)? = nil,
		presenting data: Binding<T?>,
		@ViewBuilder actions: (T) -> some View
	) -> some View {
		alert2(
			title: { title($0) },
			presenting: data,
			actions: actions,
			message: { // swiftlint:disable:this trailing_closure
				if let message = message?($0) {
					Text(message)
				}
			}
		)
	}

	// This is a convenience method and does not exist natively.
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2<T>(
		title: (T) -> String,
		message: ((T) -> String?)? = nil,
		presenting data: Binding<T?>,
		@ViewBuilder actions: (T) -> some View
	) -> some View {
		alert2(
			title: { Text(title($0)) },
			message: message,
			presenting: data,
			actions: actions
		)
	}

	// This is a convenience method and does not exist natively.
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2<T>(
		title: (T) -> Text,
		message: ((T) -> String?)? = nil,
		presenting data: Binding<T?>
	) -> some View {
		alert2(
			title: title,
			message: message,
			presenting: data,
			actions: { _ in } // swiftlint:disable:this trailing_closure
		)
	}

	// This is a convenience method and does not exist natively.
	/**
	This allows multiple alerts on a single view, which `.alert()` doesn't.
	*/
	func alert2<T>(
		title: (T) -> String,
		message: ((T) -> String?)? = nil,
		presenting data: Binding<T?>
	) -> some View {
		alert2(
			title: { Text(title($0)) },
			message: message,
			presenting: data
		)
	}
}


// Multiple `.confirmationDialog` are broken in iOS 15.0
extension View {
	/**
	This allows multiple confirmation dialogs on a single view, which `.confirmationDialog()` doesn't.
	*/
	func confirmationDialog2(
		_ title: Text,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: () -> some View,
		@ViewBuilder message: () -> some View
	) -> some View {
		background(
			EmptyView()
				.confirmationDialog(
					title,
					isPresented: isPresented,
					titleVisibility: titleVisibility,
					actions: actions,
					message: message
				)
		)
	}

	/**
	This allows multiple confirmation dialogs on a single view, which `.confirmationDialog()` doesn't.
	*/
	func confirmationDialog2(
		_ title: Text,
		message: String? = nil,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: () -> some View
	) -> some View {
		confirmationDialog2(
			title,
			isPresented: isPresented,
			titleVisibility: titleVisibility,
			actions: actions,
			message: { // swiftlint:disable:this trailing_closure
				if let message {
					Text(message)
				}
			}
		)
	}

	/**
	This allows multiple confirmation dialogs on a single view, which `.confirmationDialog()` doesn't.
	*/
	func confirmationDialog2(
		_ title: String,
		message: String? = nil,
		isPresented: Binding<Bool>,
		titleVisibility: Visibility = .automatic,
		@ViewBuilder actions: () -> some View
	) -> some View {
		confirmationDialog2(
			Text(title),
			message: message,
			isPresented: isPresented,
			titleVisibility: titleVisibility,
			actions: actions
		)
	}
}


// This exist as the new `item`-type alert APIs in iOS 15 are shit.
extension View {
	// This is a convenience method and does not exist natively.
	/**
	This allows multiple confirmation dialogs on a single view, which `.confirmationDialog()` doesn't.
	*/
	func confirmationDialog2<T>(
		title: (T) -> Text,
		titleVisibility: Visibility = .automatic,
		presenting data: Binding<T?>,
		@ViewBuilder actions: (T) -> some View,
		@ViewBuilder message: (T) -> some View
	) -> some View {
		background(
			EmptyView()
				.confirmationDialog(
					data.wrappedValue.map(title) ?? Text(""),
					isPresented: data.isPresent(),
					titleVisibility: titleVisibility,
					presenting: data.wrappedValue,
					actions: actions,
					message: message
				)
		)
	}

	// This is a convenience method and does not exist natively.
	/**
	This allows multiple confirmation dialogs on a single view, which `.confirmationDialog()` doesn't.
	*/
	func confirmationDialog2<T>(
		title: (T) -> Text,
		message: ((T) -> String?)? = nil,
		titleVisibility: Visibility = .automatic,
		presenting data: Binding<T?>,
		@ViewBuilder actions: (T) -> some View
	) -> some View {
		confirmationDialog2(
			title: { title($0) },
			titleVisibility: titleVisibility,
			presenting: data,
			actions: actions,
			message: { // swiftlint:disable:this trailing_closure
				if let message = message?($0) {
					Text(message)
				}
			}
		)
	}

	// This is a convenience method and does not exist natively.
	/**
	This allows multiple confirmation dialogs on a single view, which `.confirmationDialog()` doesn't.
	*/
	func confirmationDialog2<T>(
		title: (T) -> String,
		message: ((T) -> String?)? = nil,
		titleVisibility: Visibility = .automatic,
		presenting data: Binding<T?>,
		@ViewBuilder actions: (T) -> some View
	) -> some View {
		confirmationDialog2(
			title: { Text(title($0)) },
			message: message,
			titleVisibility: titleVisibility,
			presenting: data,
			actions: actions
		)
	}
}


struct ImageView: NSViewRepresentable {
	typealias NSViewType = NSImageView

	let image: NSImage

	func makeNSView(context: Context) -> NSViewType {
		let nsView = NSImageView()
		nsView.wantsLayer = true
		nsView.translatesAutoresizingMaskIntoConstraints = false
		nsView.setContentHuggingPriority(.defaultHigh, for: .vertical)
		nsView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
		return nsView
	}

	func updateNSView(_ nsView: NSViewType, context: Context) {
		nsView.image = image
	}

	func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
		guard let size = proposal.toCGSize else {
			return nil
		}

		return image.size.aspectFitInside(size)
	}
}


extension ProposedViewSize {
	var toCGSize: CGSize? {
		guard
			let width,
			let height
		else {
			return nil
		}

		return .init(width: width, height: height)
	}
}


extension CGSize {
	/**
	Returns a new size that fits within a target size while maintaining the aspect ratio and ensuring it does not exceed the original size.

	- Parameter targetSize: The target size within which the original size should fit.
	- Returns: A new size fitting within `targetSize` and not exceeding the original size.

	Use-cases:
	- Scaling images without distortion.
	- Adapting a UI element size to fit within certain bounds without exceeding its original dimensions.
	*/
	func aspectFitInside(_ targetSize: Self) -> Self {
		let originalAspectRatio = width / height
		let targetAspectRatio = targetSize.width / targetSize.height


		var newSize = if targetAspectRatio > originalAspectRatio {
			CGSize(width: targetSize.height * originalAspectRatio, height: targetSize.height)
		} else {
			CGSize(width: targetSize.width, height: targetSize.width / originalAspectRatio)
		}

		// Ensure the size is not larger than the original.
		newSize.width = min(newSize.width, width)
		newSize.height = min(newSize.height, height)

		return newSize
	}
}


extension SetAlgebra {
	/**
	Insert the `value` if it doesn't exist, otherwise remove it.
	*/
	mutating func toggleExistence(_ value: Element) {
		if contains(value) {
			remove(value)
		} else {
			insert(value)
		}
	}

	/**
	Insert the `value` if `shouldExist` is true, otherwise remove it.
	*/
	mutating func toggleExistence(_ value: Element, shouldExist: Bool) {
		if shouldExist {
			insert(value)
		} else {
			remove(value)
		}
	}
}


private struct WindowAccessor: NSViewRepresentable {
	private final class WindowAccessorView: NSView {
		@Binding var windowBinding: NSWindow?

		init(binding: Binding<NSWindow?>) {
			self._windowBinding = binding
			super.init(frame: .zero)
		}

		override func viewWillMove(toWindow newWindow: NSWindow?) {
			super.viewWillMove(toWindow: newWindow)

			guard let newWindow else {
				return
			}

			windowBinding = newWindow
		}

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			windowBinding = window
		}

		@available(*, unavailable)
		required init?(coder: NSCoder) {
			fatalError("") // swiftlint:disable:this fatal_error_message
		}
	}

	@Binding var window: NSWindow?

	init(_ window: Binding<NSWindow?>) {
		self._window = window
	}

	func makeNSView(context: Context) -> NSView {
		WindowAccessorView(binding: $window)
	}

	func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
	/**
	Bind the native backing-window of a SwiftUI window to a property.
	*/
	func bindHostingWindow(_ window: Binding<NSWindow?>) -> some View {
		background(WindowAccessor(window))
	}
}

private struct WindowViewModifier: ViewModifier {
	@State private var window: NSWindow?

	let onWindow: (NSWindow?) -> Void

	func body(content: Content) -> some View {
		// We're intentionally not using `.onChange` as we need it to execute for every SwiftUI change as the window properties can be changed at any time by SwiftUI.
		onWindow(window)

		return content
			.bindHostingWindow($window)
	}
}

extension View {
	/**
	Access the native backing-window of a SwiftUI window.
	*/
	func accessHostingWindow(_ onWindow: @escaping (NSWindow?) -> Void) -> some View {
		modifier(WindowViewModifier(onWindow: onWindow))
	}

	/**
	Set the window tabbing mode of a SwiftUI window.
	*/
	func windowTabbingMode(_ tabbingMode: NSWindow.TabbingMode) -> some View {
		accessHostingWindow {
			$0?.tabbingMode = tabbingMode
		}
	}

	/**
	Set whether the SwiftUI window should be resizable.

	Setting this to false disables the green zoom button on the window.
	*/
	func windowIsResizable(_ isResizable: Bool = true) -> some View {
		accessHostingWindow {
			$0?.styleMask.toggleExistence(.resizable, shouldExist: isResizable)
		}
	}

	/**
	Set whether the SwiftUI window should be restorable.
	*/
	func windowIsRestorable(_ isRestorable: Bool = true) -> some View {
		accessHostingWindow {
			$0?.isRestorable = isRestorable
		}
	}

	/**
	Make a SwiftUI window draggable by clicking and dragging anywhere in the window.
	*/
	func windowIsMovableByWindowBackground(_ isMovableByWindowBackground: Bool = true) -> some View {
		accessHostingWindow {
			$0?.isMovableByWindowBackground = isMovableByWindowBackground
		}
	}

	/**
	Set whether to show the title bar appears transparent.
	*/
	func windowTitlebarAppearsTransparent(_ isActive: Bool = true) -> some View {
		accessHostingWindow { window in
			window?.titlebarAppearsTransparent = isActive
		}
	}

	/**
	Set the collection behavior of a SwiftUI window.
	*/
	func windowCollectionBehavior(_ collectionBehavior: NSWindow.CollectionBehavior) -> some View {
		accessHostingWindow { window in
			window?.collectionBehavior = collectionBehavior

			// This is needed on windows with `.windowResizability(.contentSize)`. (macOS 13.4)
			// If it's not set, the window will not show in fullscreen mode for some reason.
			DispatchQueue.main.async {
				window?.collectionBehavior = collectionBehavior
			}
		}
	}

	func windowIsVibrant() -> some View {
		accessHostingWindow {
			$0?.makeVibrant()
		}
	}
}


extension NSColor {
	convenience init(light: NSColor, dark: NSColor?) {
		self.init(name: nil) { $0.isDarkMode ? (dark ?? light) : light }
	}
}

extension Color {
	init(dynamicProvider: @escaping (Bool) -> Self) {
		self.init(
			NSColor(name: nil) {
				NSColor(dynamicProvider($0.isDarkMode))
			}
		)
	}
}


extension Color {
	init(light: Self, dark: Self?) {
		self.init { $0 ? (dark ?? light) : light }
	}
}


extension NSAppearance {
	var isDarkMode: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}


extension FloatingPointFormatStyle.Percent {
	/**
	Do not show fraction.
	*/
	var noFraction: Self { precision(.fractionLength(0)) }
}


private struct EqualWidthWithBindingPreferenceKey: PreferenceKey {
	static let defaultValue = 0.0

	static func reduce(value: inout Double, nextValue: () -> Double) {
		value = nextValue()
	}
}

private struct EqualWidthWithBinding: ViewModifier {
	@Binding var width: Double?
	let alignment: Alignment

	func body(content: Content) -> some View {
		content
			.frame(width: width?.nilIfZero?.toCGFloat, alignment: alignment)
			.background {
				GeometryReader {
					Color.clear
						.preference(
							key: EqualWidthWithBindingPreferenceKey.self,
							value: $0.size.width
						)
				}
			}
			.onPreferenceChange(EqualWidthWithBindingPreferenceKey.self) {
				width = max(width ?? 0, $0)
			}
	}
}

extension View {
	func equalWidthWithBinding(
		_ width: Binding<Double?>,
		alignment: Alignment = .center
	) -> some View {
		modifier(EqualWidthWithBinding(width: width, alignment: alignment))
	}
}


extension PrimitiveButtonStyle where Self == WidthButtonStyle {
	/**
	Make button have equal width.
	*/
	static func equalWidth(
		_ width: Binding<Double?>,
		minimumWidth: Double? = nil
	) -> Self {
		.init(
			width: width,
			minimumWidth: minimumWidth
		)
	}
}

struct WidthButtonStyle: PrimitiveButtonStyle {
	@Binding var width: Double?
	var minimumWidth: Double?

	func makeBody(configuration: Configuration) -> some View {
		Button(role: configuration.role) {
			configuration.trigger()
		} label: {
			configuration.label
				.frame(minWidth: minimumWidth?.toCGFloat)
				.equalWidthWithBinding($width)
		}
	}
}


extension StringProtocol {
	@inlinable
	var isWhitespace: Bool {
		allSatisfy(\.isWhitespace)
	}

	@inlinable
	var isEmptyOrWhitespace: Bool { isEmpty || isWhitespace }
}


extension Collection {
	/**
	Works on strings too, since they're just collections.
	*/
	@inlinable
	var nilIfEmpty: Self? { isEmpty ? nil : self }
}

extension StringProtocol {
	@inlinable
	var nilIfEmptyOrWhitespace: Self? { isEmptyOrWhitespace ? nil : self }
}

extension AdditiveArithmetic {
	/**
	Returns `nil` if the value is `0`.
	*/
	@inlinable
	var nilIfZero: Self? { self == .zero ? nil : self }
}

extension CGSize {
	/**
	Returns `nil` if the value is `0`.
	*/
	@inlinable
	var nilIfZero: Self? { self == .zero ? nil : self }
}

extension CGRect {
	/**
	Returns `nil` if the value is `0`.
	*/
	@inlinable
	var nilIfZero: Self? { self == .zero ? nil : self }
}


struct CopyButton: View {
	@State private var isShowingSuccess = false
	private let action: () -> Void

	init(_ action: @escaping () -> Void) {
		self.action = action
	}

	var body: some View {
		Button {
			isShowingSuccess = true

			Task {
				try? await Task.sleep(for: .seconds(1))
				isShowingSuccess = false
			}

			action()
		} label: {
			Label("Copy", systemImage: "doc.on.doc")
				.opacity(isShowingSuccess ? 0 : 1)
				.overlay {
					if isShowingSuccess {
						Image(systemName: "checkmark")
							.bold()
					}
				}
		}
			.disabled(isShowingSuccess)
			.animation(.easeInOut(duration: 0.3), value: isShowingSuccess)
	}
}


extension IntentFile {
	/**
	Write the data to a unique temporary path and return the `URL`.
	*/
	func writeToUniqueTemporaryFile() throws -> URL {
		try data.writeToUniqueTemporaryFile(
			filename: filename,
			contentType: type ?? .data
		)
	}
}


extension Data {
	/**
	Create an `IntentFile` from the data.
	*/
	func toIntentFile(
		contentType: UTType,
		filename: String? = nil
	) -> IntentFile {
		.init(
			data: self,
			filename: filename ?? "file",
			type: contentType
		)
	}
}


extension Data {
	/**
	Write the data to a unique temporary path and return the `URL`.

	By default, the file has no file extension.
	*/
	func writeToUniqueTemporaryFile(
		filename: String? = nil,
		contentType: UTType = .data
	) throws -> URL {
		let destinationUrl = try URL.uniqueTemporaryDirectory()
			.appendingPathComponent(filename ?? "file", conformingTo: contentType)

		try write(to: destinationUrl)

		return destinationUrl
	}
}


extension URL {
	/**
	Creates a unique temporary directory and returns the URL.

	The URL is unique for each call.

	The system ensures the directory is not cleaned up until after the app quits.
	*/
	static func uniqueTemporaryDirectory(
		appropriateFor: Self? = nil
	) throws -> Self {
		try FileManager.default.url(
			for: .itemReplacementDirectory,
			in: .userDomainMask,
			appropriateFor: appropriateFor ?? URL.temporaryDirectory,
			create: true
		)
	}

	/**
	Copy the file at the current URL to a unique temporary directory and return the new URL.
	*/
	func copyToUniqueTemporaryDirectory(filename: String? = nil) throws -> Self {
		let destinationUrl = try Self.uniqueTemporaryDirectory(appropriateFor: self)
			.appendingPathComponent(filename ?? lastPathComponent, isDirectory: false)

		try FileManager.default.copyItem(at: self, to: destinationUrl)

		return destinationUrl
	}
}


extension View {
	@ViewBuilder
	func `if`(
		_ condition: @autoclosure () -> Bool,
		modify: (Self) -> some View
	) -> some View {
		if condition() {
			modify(self)
		} else {
			self
		}
	}

	func `if`(
		_ condition: @autoclosure () -> Bool,
		modify: (Self) -> Self
	) -> Self {
		condition() ? modify(self) : self
	}
}


extension View {
	@ViewBuilder
	func `if`(
		_ condition: @autoclosure () -> Bool,
		if modifyIf: (Self) -> some View,
		else modifyElse: (Self) -> some View
	) -> some View {
		if condition() {
			modifyIf(self)
		} else {
			modifyElse(self)
		}
	}

	func `if`(
		_ condition: @autoclosure () -> Bool,
		if modifyIf: (Self) -> Self,
		else modifyElse: (Self) -> Self
	) -> Self {
		condition() ? modifyIf(self) : modifyElse(self)
	}
}


extension ProgressViewStyleConfiguration {
	var isFinished: Bool {
		(fractionCompleted ?? 0) >= 1
	}
}


struct CircularProgressViewStyle: ProgressViewStyle {
	private struct CheckmarkShape: Shape {
		func path(in rect: CGRect) -> Path {
			Path {
				$0.move(to: CGPoint(x: rect.width * 0.3, y: rect.height * 0.52))
				$0.addLine(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.68))
				$0.addLine(to: CGPoint(x: rect.width * 0.7, y: rect.height * 0.34))
			}
		}
	}

	private let fill: AnyShapeStyle
	private let lineWidth: Double
	private let text: String?

	init(
		fill: (some ShapeStyle)? = nil,
		lineWidth: Double? = nil,
		text: String? = nil
	) {
		self.fill = fill.flatMap(AnyShapeStyle.init) ?? AnyShapeStyle(LinearGradient(gradient: .init(colors: [.purple, .blue]), startPoint: .top, endPoint: .bottom))
		self.lineWidth = lineWidth ?? 12
		self.text = text
	}

	func makeBody(configuration: Configuration) -> some View {
		let progress = configuration.fractionCompleted ?? 0
		ZStack {
			// Background
			Circle()
				.stroke(lineWidth: lineWidth)
				.opacity(0.3)
				.foregroundStyle(.secondary)
				.visualEffectsViewVibrancy(0.5)
			// Progress
			Circle()
				.trim(from: 0, to: progress)
				.stroke(fill, style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
				.rotationEffect(.init(degrees: 270))
				.saturation((progress * 2).clamped(to: 0.5...1.2))
				.animation(.easeInOut, value: progress)
			if !configuration.isFinished {
				if let text {
					Text(text)
						.fontDesign(.rounded)
						.minimumScaleFactor(0.4)
						.foregroundStyle(.secondary)
				} else {
					Text(progress.formatted(.percent.precision(.fractionLength(0))))
						.font(.system(size: 30, weight: .bold, design: .rounded))
						.monospacedDigit()
				}
			}
			CheckmarkShape()
				.stroke(style: .init(lineWidth: lineWidth / 1.5, lineCap: .round, lineJoin: .round))
				.scaleEffect(configuration.isFinished ? 1 : 0.4)
				.animation(.spring(response: 0.55, dampingFraction: 0.35).speed(1.3), value: configuration.isFinished)
				.opacity(configuration.isFinished ? 1 : 0)
				.animation(.easeInOut, value: configuration.isFinished)
				.scaledToFit()
		}
	}
}

extension ProgressViewStyle where Self == CircularProgressViewStyle {
	static func ssCircular(
		fill: (some ShapeStyle)? = nil,
		lineWidth: Double? = nil,
		text: String? = nil
	) -> Self {
		.init(
			fill: fill,
			lineWidth: lineWidth,
			text: text
		)
	}
}


extension View {
	/**
	Add a keyboard shortcut to a view, not a button.
	*/
	func onKeyboardShortcut(
		_ shortcut: KeyboardShortcut?,
		perform action: @escaping () -> Void
	) -> some View {
		overlay {
			Button("", action: action)
				.labelsHidden()
				.opacity(0)
				.frame(width: 0, height: 0)
				.keyboardShortcut(shortcut)
				.accessibilityHidden(true)
		}
	}

	/**
	Add a keyboard shortcut to a view, not a button.
	*/
	func onKeyboardShortcut(
		_ key: KeyEquivalent,
		modifiers: SwiftUI.EventModifiers = .command,
		isEnabled: Bool = true,
		perform action: @escaping () -> Void
	) -> some View {
		onKeyboardShortcut(isEnabled ? .init(key, modifiers: modifiers) : nil, perform: action)
	}
}


extension Device {
	static var isReduceMotionEnabled: Bool {
		#if os(macOS)
		NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		#else
		UIAccessibility.isReduceMotionEnabled
		#endif
	}
}


func withAnimationIf<Result>(
	_ condition: Bool,
	animation: Animation? = .default,
	_ body: () throws -> Result
) rethrows -> Result {
	condition
		? try withAnimation(animation, body)
		: try body()
}

func withAnimationWhenNotReduced<Result>(
	_ animation: Animation? = .default,
	_ body: () throws -> Result
) rethrows -> Result {
	try withAnimationIf(
		!Device.isReduceMotionEnabled,
		animation: animation,
		body
	)
}


struct AnyDropDelegate: DropDelegate {
	var isTargeted: Binding<Bool>?
	var onValidate: ((DropInfo) -> Bool)?
	let onPerform: (DropInfo) -> Bool
	var onEntered: ((DropInfo) -> Void)?
	var onExited: ((DropInfo) -> Void)?
	var onUpdated: ((DropInfo) -> DropProposal?)?

	func performDrop(info: DropInfo) -> Bool {
		onPerform(info)
	}

	func validateDrop(info: DropInfo) -> Bool {
		onValidate?(info) ?? true
	}

	func dropEntered(info: DropInfo) {
		isTargeted?.wrappedValue = true
		onEntered?(info)
	}

	func dropExited(info: DropInfo) {
		isTargeted?.wrappedValue = false
		onExited?(info)
	}

	func dropUpdated(info: DropInfo) -> DropProposal? {
		onUpdated?(info)
	}
}


extension DropInfo {
	/**
	This is useful as `DropInfo` usually on has `NSItemProvider` items and they have to be fetched async, while the validation has to happen synchronously.
	*/
	func fileURLsConforming(to contentTypes: [UTType]) -> [URL] {
		NSPasteboard(name: .drag).fileURLs(contentTypes: contentTypes)
	}

	/**
	Indicates whether at least one file URL conforms to at least one of the specified uniform type identifiers.
	*/
	func hasFileURLsConforming(to contentTypes: [UTType]) -> Bool {
		!fileURLsConforming(to: contentTypes).isEmpty
	}
}


extension CGSize {
	var toInt: (width: Int, height: Int) {
		(Int(width), Int(height))
	}

	var videoSizeDescription: String {
		"\(Int(width))x\(Int(height))"
	}
}


extension ClosedRange<Double> {
	var toInt: ClosedRange<Int> {
		Int(lowerBound)...Int(upperBound)
	}
}

extension Range<Double> {
	var toInt: Range<Int> {
		Int(lowerBound)..<Int(upperBound)
	}
}


extension AVPlayerView {
	/**
	Activates trim mode without waiting for trimming to finish.
	*/
	func activateTrimming() async throws { // TODO: `throws(CancellationError)` when `checkCancellation` has typed throws.
		_ = await updates(for: \.canBeginTrimming).first(where: \.self)

		try Task.checkCancellation()

		Task {
			/**
			In about 20% of debug sessions, `beginTrimming` will crash because `canBeginTrimming` is false. We have seen multiple cases where this guard catches into the else statement and the trimming controls work just fine: in each and every case where `canBeginTrimming` was false, this function gets called again with a value of true.
			*/
			guard canBeginTrimming else {
				return
			}

			await beginTrimming()
		}

		await Task.yield()
	}
}


extension NSObjectProtocol where Self: NSObject {
	func updates<Value>(
		for keyPath: KeyPath<Self, Value>,
		options: NSKeyValueObservingOptions = [.initial, .new]
	) -> some AsyncSequence<Value, Never> {
		publisher(for: keyPath, options: options).toAsyncSequence
	}
}


protocol ReflectiveEquatable: Equatable {}

extension ReflectiveEquatable {
	var reflectedValue: String { String(reflecting: self) }

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.reflectedValue == rhs.reflectedValue
	}
}

protocol ReflectiveHashable: Hashable, ReflectiveEquatable {}

extension ReflectiveHashable {
	func hash(into hasher: inout Hasher) {
		hasher.combine(reflectedValue)
	}
}


extension CGSize {
	/**
	Calculates a new size that maintains the aspect ratio, based on given width or height constraints.
	If only one dimension is provided, calculates the other dimension accordingly to preserve the aspect ratio.
	If both dimensions are provided, adjusts them to fit within the given dimensions while maintaining the aspect ratio.
	*/
	func aspectFittedSize(targetWidth: Double?, targetHeight: Double?) -> Self {
		let originalAspectRatio = width / height

		switch (targetWidth, targetHeight) {
		case (let width?, nil):
			return CGSize(
				width: width,
				height: width / originalAspectRatio
			)
		case (nil, let height?):
			return CGSize(
				width: height * originalAspectRatio,
				height: height
			)
		case (let width?, let height?):
			let targetAspectRatio = width / height

			if originalAspectRatio > targetAspectRatio {
				return CGSize(
					width: width,
					height: width / originalAspectRatio
				)
			}

			return CGSize(
				width: height * originalAspectRatio,
				height: height
			)
		default:
			return self
		}
	}

	func aspectFittedSize(targetWidthHeight: Double) -> Self {
		aspectFittedSize(
			targetWidth: targetWidthHeight,
			targetHeight: targetWidthHeight
		)
	}

	func aspectFittedSize(targetWidth: Int?, targetHeight: Int?) -> Self {
		aspectFittedSize(
			targetWidth: targetWidth.flatMap { Double($0) },
			targetHeight: targetHeight.flatMap { Double($0) }
		)
	}
}


@dynamicMemberLookup
struct Tuple3<A, B, C> {
	let (first, second, third): (A, B, C)

	init(_ first: A, _ second: B, _ third: C) {
		(self.first, self.second, self.third) = (first, second, third)
	}

	subscript<T>(dynamicMember keyPath: KeyPath<(A, B, C), T>) -> T {
		(first, second, third)[keyPath: keyPath]
	}
}

extension Tuple3: Equatable where A: Equatable, B: Equatable, C: Equatable {}
extension Tuple3: Hashable where A: Hashable, B: Hashable, C: Hashable {}
extension Tuple3: Encodable where A: Encodable, B: Encodable, C: Encodable {}
extension Tuple3: Decodable where A: Decodable, B: Decodable, C: Decodable {}
extension Tuple3: Sendable where A: Sendable, B: Sendable, C: Sendable {}


@propertyWrapper
struct ViewStorage<Value>: DynamicProperty {
	private final class ValueBox {
		var value: Value

		init(_ value: Value) {
			self.value = value
		}
	}

	@State private var valueBox: ValueBox

	var wrappedValue: Value {
		get { valueBox.value }
		nonmutating set {
			valueBox.value = newValue
		}
	}

	var projectedValue: Binding<Value> {
		.init(
			get: { wrappedValue },
			set: {
				wrappedValue = $0
			}
		)
	}

	init(wrappedValue value: @autoclosure @escaping () -> Value) {
		self._valueBox = .init(wrappedValue: ValueBox(value()))
	}
}


extension SSApp {
	final class Activity {
		private let activity: NSObjectProtocol

		init(
			_ options: ProcessInfo.ActivityOptions = [],
			reason: String
		) {
			self.activity = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
		}

		deinit {
			ProcessInfo.processInfo.endActivity(activity)
		}
	}

	static func beginActivity(
		_ options: ProcessInfo.ActivityOptions = [],
		reason: String
	) -> Activity {
		.init(options, reason: reason)
	}
}

extension View {
	func activity(
		_ isActive: Bool = true,
		options: ProcessInfo.ActivityOptions = [],
		reason: String
	) -> some View {
		modifier(
			AppActivityModifier(
				isActive: isActive,
				options: options,
				reason: reason
			)
		)
	}
}

private struct AppActivityModifier: ViewModifier {
	@ViewStorage private var activity: SSApp.Activity?

	let isActive: Bool
	let options: ProcessInfo.ActivityOptions
	let reason: String

	func body(content: Content) -> some View {
		content
			.task(id: Tuple3(isActive, options, reason)) { // TODO: Use a tuple here when it can be equatable.
				activity = isActive ? SSApp.beginActivity(options, reason: reason) : nil
			}
	}
}


func greatestCommonDivisor<T: BinaryInteger>(_ a: T, _ b: T) -> T {
	let result = a % b
	return result == 0 ? b : greatestCommonDivisor(b, result)
}


extension View {
	func staticPopover(
		isPresented: Binding<Bool>,
		@ViewBuilder content: @escaping () -> some View
	) -> some View {
		modifier(
			StaticPopover(
				isPresented: isPresented,
				popoverContent: content
			)
		)
	}
}

/**
Use the size of the select box when it is opened, so the popover doesn't move as the select box changes shape.
*/
struct StaticPopover<PopoverContent: View>: ViewModifier {
	@State private var size: CGSize?
	@State private var visibleSize: CGSize?

	@Binding var isPresented: Bool
	let popoverContent: () -> PopoverContent

	func body(content: Content) -> some View {
		ZStack(alignment: .trailing) {
			content
				.readSize(into: $size)
				.onChange(of: isPresented) {
					visibleSize = size
				}
			if isPresented {
				Color.clear
					.fillFrame()
					.frame(width: visibleSize?.width, height: visibleSize?.height)
					.popover2(isPresented: $isPresented, arrowEdge: .bottom) {
						popoverContent()
					}
			}
		}
	}
}


extension View {
	func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
		onGeometryChange(for: CGSize.self) { proxy in
			proxy.size
		} action: {
			onChange($0)
		}
	}

	func readSize(into binding: Binding<CGSize?>) -> some View {
		readSize {
			binding.wrappedValue = $0
		}
	}
}


extension ColorScheme {
	var isDark: Bool {
		self == .dark
	}
}


extension Color {
	var ciColor: CIColor? {
		CIColor(color: NSColor(self))
	}

	var simd4: SIMD4<Float> {
		let color = NSColor(self)
		return .init(
			x: Float(color.redComponent),
			y: Float(color.greenComponent),
			z: Float(color.blueComponent),
			w: Float(color.alphaComponent)
		)
	}
}


extension CVPixelBuffer {
	var planeCount: Int {
		CVPixelBufferGetPlaneCount(self)
	}

	var width: Int {
		CVPixelBufferGetWidth(self)
	}

	var height: Int {
		CVPixelBufferGetHeight(self)
	}

	var pixelFormatType: OSType {
		CVPixelBufferGetPixelFormatType(self)
	}

	var bytesPerRow: Int {
		CVPixelBufferGetBytesPerRow(self)
	}

	var baseAddress: UnsafeMutableRawPointer? {
		CVPixelBufferGetBaseAddress(self)
	}

	var creationAttributes: [String: Any] {
		CVPixelBufferCopyCreationAttributes(self) as NSDictionary as? [String: Any] ?? [:]
	}

	var attachments: [String: Any] {
		guard let attachments = CVBufferCopyAttachments(self, .shouldPropagate) else {
			return [:]
		}

		return attachments as NSDictionary as? [String: Any] ?? [:]
	}

	func baseAddressOfPlane(_ plane: Int) -> UnsafeMutableRawPointer? {
		CVPixelBufferGetBaseAddressOfPlane(self, plane)
	}

	func bytesPerRowOfPlane(_ plane: Int) -> Int {
		CVPixelBufferGetBytesPerRowOfPlane(self, plane)
	}

	func heightOfPlane(_ plane: Int) -> Int {
		CVPixelBufferGetHeightOfPlane(self, plane)
	}

	var colorSpace: CGColorSpace? {
		attachments[kCVImageBufferCGColorSpaceKey as String] as! CGColorSpace?
	}

	static func create(
		width: Int,
		height: Int,
		pixelFormatType: OSType,
		pixelBufferAttributes: [String: Any]? = nil // swiftlint:disable:this discouraged_optional_collection
	) throws(CreationError) -> CVPixelBuffer {
		var out: CVPixelBuffer?
		let status = CVPixelBufferCreate(
			kCFAllocatorDefault,
			width,
			height,
			pixelFormatType,
			pixelBufferAttributes as CFDictionary?,
			&out
		)

		guard status == kCVReturnSuccess else {
			throw .creationError(status: status)
		}

		guard let out else {
			throw .noBuffer
		}

		return out
	}

	enum CreationError: Error {
		case creationError(status: CVReturn)
		case noBuffer
	}

	func copy(to destination: CVPixelBuffer) throws {
		try withLockedPlanes(flags: [.readOnly]) { sourcePlanes in
			try destination.withLockedPlanes(flags: []) { destinationPlanes in
				guard sourcePlanes.count == destinationPlanes.count else {
					throw CopyError.planesMismatch
				}

				for (sourcePlane, destinationPlane) in zip(sourcePlanes, destinationPlanes) {
					try sourcePlane.copy(to: destinationPlane)
				}
			}
		}
	}

	func lockBaseAddress(flags: CVPixelBufferLockFlags = []) throws(LockError) {
		let status = CVPixelBufferLockBaseAddress(self, flags)

		guard status == kCVReturnSuccess else {
			throw .lockFailed(status: status)
		}
	}

	enum LockError: Error {
		case lockFailed(status: CVReturn)
		case noBaseAddress
	}

	func unlockBaseAddress(flags: CVPixelBufferLockFlags = []) {
		CVPixelBufferUnlockBaseAddress(self, flags)
	}

	enum CopyError: Error {
		case planesMismatch
		case heightMismatch
	}

	func withLockedBaseAddress<T>(
		flags: CVPixelBufferLockFlags = [],
		_ body: (CVPixelBuffer) throws -> T
	) throws -> T {
		try lockBaseAddress(flags: flags)

		defer {
			self.unlockBaseAddress(flags: flags)
		}

		return try body(self)
	}

	func withLockedPlanes<T>(
		flags: CVPixelBufferLockFlags = [],
		_ body: ([LockedPlane]) throws -> T
	) throws -> T {
		try withLockedBaseAddress(flags: flags) { buffer in
			let planeCount = buffer.planeCount

			if planeCount == 0 {
				guard let baseAddress = buffer.baseAddress else {
					throw LockError.noBaseAddress
				}

				return try body([
					.init(
						base: baseAddress,
						bytesPerRow: buffer.bytesPerRow,
						height: buffer.height
					)
				])
			}

			let planes = try (0..<planeCount).compactMap { planeIndex -> LockedPlane? in
				guard let baseAddress = buffer.baseAddressOfPlane(planeIndex) else {
					throw LockError.noBaseAddress
				}

				return .init(
					base: baseAddress,
					bytesPerRow: buffer.bytesPerRowOfPlane(planeIndex),
					height: buffer.heightOfPlane(planeIndex)
				)
			}

			guard planes.count == planeCount else {
				throw CopyError.planesMismatch
			}

			return try body(planes)
		}
	}

	func makeCompatibleBuffer() throws(CreationError) -> CVPixelBuffer {
		try Self.create(
			width: width,
			height: height,
			pixelFormatType: pixelFormatType,
			pixelBufferAttributes: creationAttributes
		)
	}

	struct LockedPlane {
		let base: UnsafeMutableRawPointer
		let bytesPerRow: Int
		let height: Int

		func copy(to destination: Self) throws(CopyError) {
			guard height == destination.height else {
				throw .heightMismatch
			}

			guard bytesPerRow != destination.bytesPerRow else {
				memcpy(destination.base, base, height * bytesPerRow)
				return
			}

			var destinationBase = destination.base
			var sourceBase = base
			let minBytesPerRow = min(bytesPerRow, destination.bytesPerRow)

			for _ in 0..<height {
				memcpy(destinationBase, sourceBase, minBytesPerRow)
				sourceBase = sourceBase.advanced(by: bytesPerRow)
				destinationBase = destinationBase.advanced(by: destination.bytesPerRow)
			}
		}
	}

	/**
	Setup the video to use sRGB color space.

	We  set `kCVImageBufferColorPrimariesKey`  and  `kCVImageBufferYCbCrMatrixKey` to 709 because sRGB and 709 "share the same primary chromaticities, but they have different transfer functions". [Source](https://web.archive.org/web/20250416122435/https://www.image-engineering.de/library/technotes/714-color-spaces-rec-709-vs-srgb)
	*/
	func setSRGBColorSpace() {
		setAttachment(key: kCVImageBufferColorPrimariesKey, value: kCVImageBufferColorPrimaries_ITU_R_709_2, attachmentMode: .shouldPropagate)
		setAttachment(key: kCVImageBufferTransferFunctionKey, value: kCVImageBufferTransferFunction_sRGB, attachmentMode: .shouldPropagate)
		setAttachment(key: kCVImageBufferYCbCrMatrixKey, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2, attachmentMode: .shouldPropagate)
	}

	func setAttachment(
		key: CFString,
		value: CFTypeRef,
		attachmentMode: CVAttachmentMode
	) {
		CVBufferSetAttachment(self, key, value, attachmentMode)
	}

	/**
	Mark that the pixel buffer will not be modified in any way except by `PreviewRenderer`.
	*/
	var previewSendable: PreviewRenderer.SendableCVPixelBuffer {
		PreviewRenderer.SendableCVPixelBuffer(pixelBuffer: self)
	}
}


extension CGImageSource {
	enum CreateError: Error {
		case failedToCreateImageSource
	}

	enum CreateImageError: Error {
		case failedToCreateImage(status: CGImageSourceStatus)
	}

	static func from(
		_ data: Data,
		options: [String: Any]? = nil // swiftlint:disable:this discouraged_optional_collection
	) throws(CreateError) -> CGImageSource {
		guard
			let imageSource = CGImageSourceCreateWithData(
				data as CFData,
				options as CFDictionary?
			)
		else {
			throw .failedToCreateImageSource
		}

		return imageSource
	}

	var count: Int {
		CGImageSourceGetCount(self)
	}

	func createImage(
		atIndex index: Int,
		options: [String: Any]? = nil // swiftlint:disable:this discouraged_optional_collection
	) throws(CreateImageError) -> CGImage {
		guard
			let image = CGImageSourceCreateImageAtIndex(
				self,
				index,
				options as CFDictionary?
			)
		else {
			throw .failedToCreateImage(status: CGImageSourceGetStatusAtIndex(self, index))
		}

		return image
	}
}

extension CGImage {
	func convertToData(
		withNewType type: String,
		destinationOptions: [String: Any]? = nil, // swiftlint:disable:this discouraged_optional_collection
		addOptions: [String: Any]? = nil // swiftlint:disable:this discouraged_optional_collection
	) throws -> Data {
		let mutableData = NSMutableData()

		let destination = try CGImageDestination.from(
			withData: mutableData,
			type: type,
			count: 1,
			options: destinationOptions
		)

		destination.addImage(self, properties: addOptions)

		try destination.finalize()

		return mutableData as Data
	}
}

extension CGImageDestination {
	static func from(
		withData: NSMutableData,
		type: String,
		count: Int = 1,
		options: [String: Any]? = nil // swiftlint:disable:this discouraged_optional_collection
	) throws(CreateError) -> CGImageDestination {
		guard
			let imageDestination = CGImageDestinationCreateWithData(
				withData,
				type as CFString,
				count,
				options as CFDictionary?
			)
		else {
			throw .failedToCreate
		}

		return imageDestination
	}

	enum CreateError: Error {
		case failedToCreate
	}

	func addImage(
		_ image: CGImage,
		properties: [String: Any]? = nil // swiftlint:disable:this discouraged_optional_collection
	) {
		CGImageDestinationAddImage(
			self,
			image,
			properties as CFDictionary?
		)
	}

	enum FinalizeError: Error {
		case failedToFinalize
	}

	func finalize() throws(FinalizeError) {
		guard CGImageDestinationFinalize(self) else {
			throw .failedToFinalize
		}
	}
}


extension Data {
	func readLittleEndianUInt24(_ start: Int) -> UInt32 {
		UInt32(self[start]) | UInt32(self[start + 1]) << 8 | UInt32(self[start + 2]) << 16
	}
}


extension MTLCommandBuffer {
	typealias RenderError = MTLCommandBufferRenderError

	/**
	Submits the commands to the GPU and awaits completion.
	*/
	func commit() async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
			addCompletedHandler { [weak self] _ in
				guard let self else {
					continuation.resume(throwing: RenderError.functionOutlivedTheCommandBuffer)
					return
				}

				guard status == .completed else {
					continuation.resume(throwing: RenderError.failedToRender(status: status))
					return
				}

				continuation.resume()
			}

			commit()
		}
	}

	/**
	Creates a render command encoder, runs your operation, then ends encoding with `endEncoding`.
	*/
	func withRenderCommandEncoder(
		renderPassDescriptor: MTLRenderPassDescriptor,
		operation: (MTLRenderCommandEncoder) throws -> Void
	) throws {
		guard let renderEncoder = makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
			throw RenderError.failedToMakeRenderCommandEncoder
		}

		defer {
			renderEncoder.endEncoding()
		}

		try operation(renderEncoder)
	}
}

enum MTLCommandBufferRenderError: Error {
	case failedToRender(status: MTLCommandBufferStatus)
	case functionOutlivedTheCommandBuffer
	case failedToMakeRenderCommandEncoder
}

extension MTLCommandQueue {
	typealias RenderError = MTLCommandQueueRenderError

	/**
	Creates a command buffer, runs your operation, commits (sends commands to the GPU), and awaits completion
	*/
	func withCommandBuffer(
		isolated actor: isolated any Actor,
		operation: (MTLCommandBuffer) throws -> Void
	) async throws {
		guard let commandBuffer = makeCommandBuffer() else {
			throw MTLCommandQueueRenderError.failedToCreateCommandBuffer
		}

		try operation(commandBuffer)
		try await commandBuffer.commit()
	}
}

enum MTLCommandQueueRenderError: Error {
	case failedToCreateCommandBuffer
}


extension CGPoint {
	var simdFloat2: SIMD2<Float> {
		.init(x: Float(x), y: Float(y))
	}

	func nearestPointInsideRectBounds(_ rect: CGRect) -> Self {
		.init(
			x: x.clamped(from: rect.minX, to: rect.maxX),
			y: y.clamped(from: rect.minY, to: rect.maxY)
		)
	}
}

extension CGSize {
	var simdFloat2: SIMD2<Float> {
		.init(x: Float(width), y: Float(height))
	}

	func clamped(within rect: CGRect) -> CGPoint {
		.init(
			x: width.clamped(from: rect.minX, to: rect.maxX),
			y: height.clamped(from: rect.minY, to: rect.maxY)
		)
	}
}


/**
We need to keep a strong reference to the `CVMetalTexture` until the GPU command completes. This struct ensures that the `CVMetalTexture` is not garbage collected as long as the `MTLTexture` is around. [See](https://developer.apple.com/documentation/corevideo/cvmetaltexturecachecreatetexturefromimage(_:_:_:_:_:_:_:_:_:))
 */
struct CVMetalTextureRefeference {
	private let coreVideoTextureReference: CVMetalTexture

	let texture: MTLTexture

	fileprivate init(
		coreVideoTextureReference: CVMetalTexture,
		texture: MTLTexture
	) {
		self.coreVideoTextureReference = coreVideoTextureReference
		self.texture = texture
	}
}


extension CVMetalTextureCache {
	enum Error: LocalizedError {
		case invalidArgument
		case allocationFailed
		case unsupported
		case invalidPixelFormat
		case invalidPixelBufferAttributes
		case invalidSize
		case pixelBufferNotMetalCompatible
		case failedToCreateTexture
		case unknown(CVReturn)

		init(cvReturn: CVReturn) {
			self = switch cvReturn {
			case kCVReturnInvalidArgument:
				.invalidArgument
			case kCVReturnAllocationFailed:
				.allocationFailed
			case kCVReturnUnsupported:
				.unsupported
			case kCVReturnInvalidPixelFormat:
				.invalidPixelFormat
			case kCVReturnInvalidPixelBufferAttributes:
				.invalidPixelBufferAttributes
			case kCVReturnInvalidSize:
				.invalidSize
			case kCVReturnPixelBufferNotMetalCompatible:
				.pixelBufferNotMetalCompatible
			default:
				.unknown(cvReturn)
			}
		}

		var errorDescription: String? {
			switch self {
			case .invalidArgument:
				"Invalid argument provided to CVMetalTextureCache"
			case .allocationFailed:
				"Memory allocation failed"
			case .unsupported:
				"Operation not supported"
			case .invalidPixelFormat:
				"Invalid pixel format"
			case .invalidPixelBufferAttributes:
				"Invalid pixel buffer attributes"
			case .invalidSize:
				"Invalid size"
			case .pixelBufferNotMetalCompatible:
				"Pixel buffer is not Metal compatible"
			case .failedToCreateTexture:
				"Failed to create Metal texture"
			case .unknown(let cvReturn):
				"Unknown CVReturn error: \(cvReturn)"
			}
		}
	}

	func createTexture(
		from image: CVPixelBuffer,
		pixelFormat: MTLPixelFormat,
		textureAttributes: [String: Any]? = nil // swiftlint:disable:this discouraged_optional_collection
	) throws(Error) -> CVMetalTextureRefeference {
		var coreVideoTextureReference: CVMetalTexture?

		let result = CVMetalTextureCacheCreateTextureFromImage(
			nil,
			self,
			image,
			textureAttributes as CFDictionary?,
			pixelFormat,
			image.width,
			image.height,
			0,
			&coreVideoTextureReference
		)

		guard result == kCVReturnSuccess else {
			throw .init(cvReturn: result)
		}

		guard
			let coreVideoTextureReference,
			let texture = CVMetalTextureGetTexture(coreVideoTextureReference)
		else {
			throw .failedToCreateTexture
		}

		return .init(
			coreVideoTextureReference: coreVideoTextureReference,
			texture: texture
		)
	}
}


/**
Support for [Adaptable Scalable Texture Compression (ASTC)](https://www.khronos.org/opengl/wiki/ASTC_Texture_Compression) images.

ASTC files have a [16-byte header](https://github.com/ARM-software/astc-encoder/blob/main/Docs/FileFormat.md). We parse it to get render information, like the size of the blocks and the image size.
*/
struct ASTCImage {
	enum CreateError: Error {
		case invalidDataSize
		case notASTCData
	}

	enum WriteError: Error {
		case failedToGetASTCBaseAddress
	}

	private static let headerSize = 16
	private static let astcBlockSize = 16

	private let data: Data
	private let blockSize: (UInt8, UInt8, UInt8)
	private let imageSize: (Int, Int, Int)

	init(data: Data) throws(CreateError) {
		self.data = data

		guard data.count >= Self.headerSize else {
			throw .invalidDataSize
		}

		// Check the magic number
		guard
			data[0] == 0x13,
			data[1] == 0xAB,
			data[2] == 0xA1,
			data[3] == 0x5C
		else {
			throw .notASTCData
		}

		self.blockSize = (data[4], data[5], data[6])

		self.imageSize = (
			Int(data.readLittleEndianUInt24(7)),
			Int(data.readLittleEndianUInt24(10)),
			Int(data.readLittleEndianUInt24(13))
		)
	}

	var width: Int {
		imageSize.0
	}

	var height: Int {
		imageSize.1
	}

	/**
	A Metal descriptor that describes this image.
	*/
	func descriptor() throws(MTLPixelFormat.ASTCPixelFormatError) -> MTLTextureDescriptor {
		MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: try .astcLowDynamicRange(fromBlockSize: blockSize),
			width: width,
			height: height,
			mipmapped: false
		)
	}

	func write(to texture: MTLTexture) throws {
		try data.withUnsafeBytes { bytes in
			guard let baseAddress = bytes.baseAddress else {
				throw WriteError.failedToGetASTCBaseAddress
			}

			let imageDataStart = baseAddress.advanced(by: Self.headerSize)

			texture.replace(
				region: MTLRegionMake2D(0, 0, width, height),
				mipmapLevel: 0,
				withBytes: imageDataStart,
				bytesPerRow: bytesPerRow
			)
		}
	}

	private var bytesPerRow: Int {
		blocksPerRow * Self.astcBlockSize
	}

	private var blocksPerRow: Int {
		Int(ceil(Double(width) / Double(blockSize.0)))
	}
}


extension MTLPixelFormat {
	enum ASTCPixelFormatError: Error {
		case notImplemented
	}

	/**
	[ASTC](https://registry.khronos.org/OpenGL/extensions/OES/OES_texture_compression_astc.txt) low dynamic range at a given block size:

	"...the number of bits per pixel that ASTC takes up is determined by the block size used. So the 4x4 version of ASTC, the smallest block size, takes up 8 bits per pixel, while the 12x12 version takes up only 0.89bpp." [*](https://www.khronos.org/opengl/wiki/ASTC_Texture_Compression)

	- Parameters:
		- blockSize: Block size in (x, y ,z)

	- Returns: the appropriate pixel format given an astc block size.
	*/
	static func astcLowDynamicRange(
		fromBlockSize blockSize: (UInt8, UInt8, UInt8)
	) throws(ASTCPixelFormatError) -> Self {
		let (width, height, depth) = blockSize

		guard depth == 1 else {
			throw .notImplemented
		}

		if
			width == 4,
			height == 4
		{
			return .astc_4x4_ldr
		}

		if
			width == 8,
			height == 8
		{
			return .astc_8x8_ldr
		}

		throw .notImplemented
	}
}


/**
A task with a progress AsyncStream.
*/
struct ProgressableTask<Progress: Sendable, Result: Sendable>: Sendable {
	let progress: AsyncStream<Progress>
	let task: Task<Result, any Error>

	init(
		operation: @escaping (AsyncStream<Progress>.Continuation) async throws -> Result
	) {
		let (progressStream, progressContinuation) = AsyncStream<Progress>.makeStream()

		self.progress = progressStream

		self.task = Task {
			do {
				let out = try await operation(progressContinuation)
				progressContinuation.finish()
				return out
			} catch {
				progressContinuation.finish()
				throw error
			}
		}
	}

	func cancel() {
		task.cancel()
	}

	var value: Result {
		get async throws {
			try await task.value
		}
	}
}

extension ProgressableTask where Progress == Double {
	func monitorProgressWithCancellation(
		progressWeight: Double = 1,
		progressOffset: Double = 0,
		progressContinuation: AsyncStream<Progress>.Continuation,
	) async throws -> Result {
		await withTaskCancellationHandler {
			for await currentProgress in progress {
				progressContinuation.yield(progressOffset + currentProgress * progressWeight)
			}
		} onCancel: {
			cancel()
		}

		try Task.checkCancellation()

		return try await value
	}

	/**
	Compose this task with another task, weighting the progress of the task by `weight`.
	*/
	func then<Result2>(
		progressWeight: Double = 0.5,
		composeWith nextTask: @Sendable @escaping (Result) async throws -> ProgressableTask<Double, Result2>
	) -> ProgressableTask<Double, Result2> {
		ProgressableTask<Double, Result2> { progressContinuation in
			let result1 = try await monitorProgressWithCancellation(
				progressWeight: progressWeight,
				progressContinuation: progressContinuation
			)

			try Task.checkCancellation()

			let task2 = try await nextTask(result1)

			try Task.checkCancellation()

			return try await task2.monitorProgressWithCancellation(
				progressWeight: 1 - progressWeight,
				progressOffset: progressWeight,
				progressContinuation: progressContinuation
			)
		}
	}
}


/**
Protocol for preview equivalence comparison using the `~=` operator.

This ignores transient properties that don't affect visual output.
*/
protocol PreviewComparable {
	static func ~= (lhs: Self, rhs: Self) -> Bool
}


extension CompositePreviewFragmentUniforms: Equatable {
	init() {
		self.init(
			videoOrigin: .one,
			videoSize: .one,
			firstColor: .zero,
			secondColor: .one,
			gridSize: 1
		)
	}

	init(isDarkMode: Bool, videoBounds: CGRect) {
		self.init(
			videoOrigin: videoBounds.origin.nearestPointInsideRectBounds(.init(origin: .zero, width: .infinity, height: .infinity)).simdFloat2,
			videoSize: videoBounds.size.clamped(within: .init(origin: .zero, width: .infinity, height: .infinity)).simdFloat2,
			firstColor: (isDarkMode ? CheckerboardViewConstants.firstColorDark : CheckerboardViewConstants.firstColorLight).simd4,
			secondColor: (isDarkMode ? CheckerboardViewConstants.secondColorDark : CheckerboardViewConstants.secondColorLight).simd4,
			gridSize: Int32(CheckerboardViewConstants.gridSize).clamped(from: 1, to: .max)
		)
	}

	public static func == (lhs: CompositePreviewFragmentUniforms, rhs: CompositePreviewFragmentUniforms) -> Bool {
		lhs.videoOrigin == rhs.videoOrigin &&
		lhs.videoSize == rhs.videoSize &&
		lhs.firstColor == rhs.firstColor &&
		lhs.secondColor == rhs.secondColor &&
		lhs.gridSize == rhs.gridSize
	}
}
