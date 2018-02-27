import Cocoa
import ProgressKit

/// TODO: Fade the progress-bar in on the first progress events
/// TODO: I will make this a separate SPM package soon
final class DockIconProgress {
	private static let appIcon = NSApp.applicationIconImage!
	private static var previousProgressValue: Double = 0
	private static var progressObserver: NSKeyValueObservation?

	private static var dockImageView = with(NSImageView()) {
		NSApp.dockTile.contentView = $0
	}

	static var progress: Progress? {
		didSet {
			if let progress = progress {
				progressObserver = progress.observe(\.fractionCompleted, options: .new) { object, _ in
					progressValue = object.fractionCompleted
				}
			}
		}
	}

	static var progressValue: Double = 0 {
		didSet {
			if previousProgressValue == 0 || (progressValue - previousProgressValue).magnitude > 0.001 {
				previousProgressValue = progressValue
				updateDockIcon()
			}
		}
	}

	enum ProgressStyle {
		case bar
		/// TODO: Make `color` optional when https://github.com/apple/swift-evolution/blob/master/proposals/0155-normalize-enum-case-representation.md is shipping in Swift
		case circle(radius: Double, color: NSColor)
		case custom(drawHandler: (_ rect: CGRect) -> Void)
	}

	static var style: ProgressStyle = .bar

	/// TODO: Make the progress smoother by also animating the steps between each call to `updateDockIcon()`
	private static func updateDockIcon() {
		DispatchQueue.global(qos: .utility).async {
			/// TODO: If the `progressValue` is 1, draw the full circle, then schedule another draw in n milliseconds to hide it
			let icon = (0..<1).contains(self.progressValue) ? self.draw() : appIcon
			DispatchQueue.main.async {
				/// TODO: Make this better by drawing in the `contentView` directly instead of using an image
				dockImageView.image = icon
				NSApp.dockTile.display()
			}
		}
	}

	private static func draw() -> NSImage {
		return NSImage(size: appIcon.size, flipped: false) { dstRect in
			NSGraphicsContext.current?.imageInterpolation = .high
			self.appIcon.draw(in: dstRect)

			switch self.style {
			case .bar:
				self.drawProgressBar(dstRect)
			case let .circle(radius, color):
				self.drawProgressCircle(dstRect, radius: radius, color: color)
			case let .custom(drawingHandler):
				drawingHandler(dstRect)
			}

			return true
		}
	}

	private static func drawProgressBar(_ dstRect: CGRect) {
		func roundedRect(_ rect: CGRect) {
			NSBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
		}

		let bar = CGRect(x: 0, y: 20, width: dstRect.width, height: 10)
		NSColor.white.withAlphaComponent(0.8).set()
		roundedRect(bar)

		let barInnerBg = bar.insetBy(dx: 0.5, dy: 0.5)
		NSColor.black.withAlphaComponent(0.8).set()
		roundedRect(barInnerBg)

		var barProgress = bar.insetBy(dx: 1, dy: 1)
		barProgress.size.width = barProgress.width * CGFloat(self.progressValue)
		NSColor.white.set()
		roundedRect(barProgress)
	}

	private static func drawProgressCircle(_ dstRect: CGRect, radius: Double, color: NSColor) {
		guard let cgContext = NSGraphicsContext.current?.cgContext else {
			return
		}

		let path = NSBezierPath()
		let startAngle: CGFloat = 90
		let endAngle = startAngle - (360 * CGFloat(self.progressValue))
		path.appendArc(
			withCenter: dstRect.center,
			radius: CGFloat(radius),
			startAngle: startAngle,
			endAngle: endAngle,
			clockwise: true
		)

		let arc = CAShapeLayer()
		arc.path = path.cgPath
		arc.lineCap = kCALineCapRound
		arc.fillColor = nil
		arc.strokeColor = color.cgColor
		arc.lineWidth = 4
		arc.cornerRadius = 3
		arc.render(in: cgContext)
	}
}


extension NSColor {
	static let appTheme = NSColor(named: NSColor.Name("Theme"))!
}

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	@IBOutlet private weak var window: NSWindow!
	let gifski = Gifski()
	var progress: Progress?

	lazy var circularProgress = with(CircularProgressView(frame: CGRect(widthHeight: 160))) {
		$0.foreground = .appTheme
		$0.strokeWidth = 2
		$0.percentLabelLayer.setAutomaticContentsScale()
		$0.percentLabelLayer.implicitAnimations = false
		$0.layer?.backgroundColor = .clear
		$0.isHidden = true
		$0.centerInWindow(window)
	}

	lazy var videoDropView = with(VideoDropView()) {
		$0.frame = window.contentView!.frame
		$0.dropText = "Drop a Video to Convert to GIF"
		$0.onComplete = { url in
			self.convert(url.first!)
		}
	}

	var hasFinishedLaunching = false
	var urlsToConvertOnLaunch: URL!
	var choosenDimensions: CGSize!
	var choosenFrameRate: Int!

	@objc dynamic var isRunning: Bool = false {
		didSet {
			if isRunning {
				videoDropView.isHidden = true
			} else {
				videoDropView.fadeIn()
			}

			circularProgress.isHidden = !isRunning
		}
	}

	func applicationWillFinishLaunching(_ notification: Notification) {
		defaults.register(defaults: [
			"NSFullScreenMenuItemEverywhere": false,
			"outputQuality": 1
		])

		with(window!) {
			$0.titleVisibility = .hidden
			$0.appearance = NSAppearance(named: .vibrantDark)
			$0.tabbingMode = .disallowed
			$0.titlebarAppearsTransparent = true
			$0.isMovableByWindowBackground = true
			$0.styleMask.remove([.resizable, .fullScreen])
			$0.styleMask.insert(.fullSizeContentView)
			$0.isRestorable = false
			$0.setFrame(CGRect(width: 360, height: 240), display: true)
			$0.center()
		}
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		hasFinishedLaunching = true
		NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = true

		gifski.onProgress = { progress in
			self.updateProgress(progress)
		}

		let view = window.contentView!
		view.addSubview(circularProgress)
		view.addSubview(videoDropView, positioned: .above, relativeTo: nil)

		window.makeKeyAndOrderFront(nil) /// TODO: This is dirty, find a better way

		if urlsToConvertOnLaunch != nil {
			convert(urlsToConvertOnLaunch)
		}
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		guard !isRunning else {
			return
		}

		guard urls.count == 1 else {
			Misc.alert(title: "Max one file", text: "You can only convert a single file at the time")
			return
		}

		let videoUrl = urls.first!

		/// TODO: Simplify this. Make a function that calls the input when the app finished launching, or right away if it already has.
		if hasFinishedLaunching {
			convert(videoUrl)
		} else {
			// This method is called before `applicationDidFinishLaunching`,
			// so we buffer it up a video is "Open with" this app
			urlsToConvertOnLaunch = videoUrl
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return true
	}

	// MARK: - First responders
	@IBAction private func openDocument(_ sender: AnyObject) {
		openPanel(sender)
	}
	// MARK: -

	@objc
	func openPanel(_ sender: AnyObject) {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = false
		panel.canCreateDirectories = false
		panel.allowedFileTypes = System.supportedVideoTypes

		panel.beginSheetModal(for: window) {
			if $0 == .OK {
				self.convert(panel.url!)
			}
		}
	}

	func updateProgress(_ progress: Progress) {
		circularProgress.progress = CGFloat(progress.fractionCompleted)

		if progress.isFinished {
			circularProgress.percentLabelLayer.string = "✔"
			circularProgress.fadeOut(delay: 1) {
				self.isRunning = false
			}
		}
	}

	func convert(_ inputUrl: URL) {
		// We already specify the UTIs we support, so this can only happen on invalid but supported files
		guard inputUrl.isSupportedVideo else {
			Misc.alert(title: "Video not supported", text: "The video you tried to convert could not be read.")
			return
		}

		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		panel.directoryURL = inputUrl.directoryURL
		panel.nameFieldStringValue = inputUrl.changingFileExtension(to: "gif").filename
		panel.prompt = "Convert"
		panel.message = "Choose where to save the GIF"

		let accessoryViewController = SavePanelAccessoryViewController()
		accessoryViewController.inputUrl = inputUrl
		panel.accessoryView = accessoryViewController.view

		panel.beginSheetModal(for: window) {
			if $0 == .OK {
				self.startConversion(inputUrl: inputUrl, outputUrl: panel.url!)
			}
		}
	}

	func startConversion(inputUrl: URL, outputUrl: URL) {
		guard !isRunning else {
			return
		}

		isRunning = true

		circularProgress.animated = false
		circularProgress.progress = 0
		circularProgress.animated = true

		progress = Progress(totalUnitCount: 1)
		progress?.becomeCurrent(withPendingUnitCount: 1)
		gifski.convertFile(
			inputUrl,
			outputUrl: outputUrl,
			quality: defaults["outputQuality"] as! Double,
			dimensions: choosenDimensions,
			frameRate: choosenFrameRate
		)
		progress?.resignCurrent()

		DockIconProgress.progress = progress
		DockIconProgress.style = .circle(radius: 55, color: .appTheme)
	}
}
