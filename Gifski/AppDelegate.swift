import Cocoa
import ProgressKit

private let defaults = UserDefaults.standard

extension NSColor {
	static let appTheme = NSColor(named: NSColor.Name("Theme"))!
}

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	@IBOutlet private weak var window: NSWindow!
	var imageView: NSImageView!
	var imageDropView: VideoDropView!
	var gifski = Gifski()

	lazy var outputQualitySlider: NSSlider = {
		let slider = NSSlider()
		slider.frame = CGRect(width: 150, height: 32)
		slider.numberOfTickMarks = 10
		slider.allowsTickMarkValuesOnly = true
		slider.doubleValue = defaults["outputQuality"] as! Double

		slider.onAction = { _ in
			defaults["outputQuality"] = slider.doubleValue
		}

		return slider
	}()

	lazy var outputQualityView: NSView = {
		let view = NSView()
		view.addSubview(outputQualitySlider)
		view.frame.width = 280
		view.frame.height = 32

		let qualityLabel = Label(text: "Quality:")
		qualityLabel.frame.y = 9
		view.addSubview(qualityLabel)
		outputQualitySlider.frame.x = qualityLabel.frame.right

		return view
	}()

	lazy var circularProgress: CircularProgressView = {
		let size: CGFloat = 160
		let view = CircularProgressView(frame: CGRect(widthHeight: size))
		view.centerInWindow(window)
		view.foreground = .appTheme
		view.strokeWidth = 2
		view.percentLabelLayer.contentsScale = 2 /// TODO: Find out why I must set this
		view.percentLabelLayer.disableAnimation()
		view.layer?.backgroundColor = .clear
		return view
	}()

	lazy var dropToConvertLabel: NSTextField = {
		let text = NSAttributedString(string: "Drop a Video to Convert")
			.applying(attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .regular)])
			.colored(with: .appTheme)
		let label = NSTextField(labelWithAttributedString: text)
		label.frame = window.contentView!.frame.centered(size: label.frame.size)
		return label
	}()

	var isInInitialState = true
	var hasFinishedLaunching = false
	var urlsToConvertOnLaunch: URL!

	@objc dynamic var isRunning: Bool = false {
		didSet {
			imageDropView.isHidden = isRunning
		}
	}

	func applicationWillFinishLaunching(_ notification: Notification) {
		defaults.register(defaults: [
			"NSFullScreenMenuItemEverywhere": false,
			"outputQuality": 1
		])

		window.titleVisibility = .hidden
		window.appearance = NSAppearance(named: .vibrantDark)
		window.tabbingMode = .disallowed
		window.titlebarAppearsTransparent = true
		window.isMovableByWindowBackground = true
		window.styleMask.remove([.resizable, .fullScreen])
		window.styleMask.insert(.fullSizeContentView)
		window.isRestorable = false
		window.setFrame(CGRect(width: 360, height: 240), display: true)
		window.center()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		hasFinishedLaunching = true
		NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = true

		gifski.onProgress = { progress in
			self.updateProgress(progress)
		}

		let view = window.contentView!

		/// TODO: Move this to a NSViewController
		view.addSubview(dropToConvertLabel)

		imageDropView = VideoDropView(frame: view.frame)
		imageDropView.onComplete = { url in
			self.convert(url.first!)
		}
		view.addSubview(imageDropView, positioned: .above, relativeTo: nil)

		window.makeKeyAndOrderFront(nil) /// TODO: This is dirty, find a better way

		if urlsToConvertOnLaunch != nil {
			convert(urlsToConvertOnLaunch)
		}
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		guard !isRunning else {
			return
		}

		guard let imageUrls = (urls.first { $0.typeIdentifier == "public.movie" }) else {
			return
		}

		/// TODO: Simplify this. Make a function that calls the input when the app finished launching, or right away if it already has.
		if hasFinishedLaunching {
			convert(imageUrls)
		} else {
			// This method is called before `applicationDidFinishLaunching`,
			// so we buffer it up if images are "Open with" this app
			urlsToConvertOnLaunch = imageUrls
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
		panel.allowsMultipleSelection = true
		panel.allowedFileTypes = ["public.movie"]

		panel.beginSheetModal(for: window) {
			if $0 == .OK {
				self.convert(panel.url!)
			}
		}
	}

	func updateProgress(_ progress: Double) {
		circularProgress.progress = CGFloat(progress)

		if progress == 1 {
			circularProgress.percentLabelLayer.string = "✔"
			isRunning = false
		}
	}

	func createSaveAccessoryView() -> NSView {
		let view = NSView(frame: CGRect(width: 280, height: 32))
		view.autoresizingMask = [.minXMargin, .maxXMargin]
		// TODO: Use auto-layout here to place and size the controls
		view.addSubview(outputQualityView)
		return view
	}

	func convert(_ inputUrl: URL) {
		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		panel.directoryURL = inputUrl.directoryURL
		panel.nameFieldStringValue = inputUrl.changingFileExtension(to: "gif").filename
		panel.prompt = "Convert"
		panel.message = "Choose where to save the GIF"
		panel.accessoryView = createSaveAccessoryView()

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

		if isInInitialState {
			isInInitialState = false
			window.contentView!.fadeOut(dropToConvertLabel)
			window.contentView!.fadeIn(circularProgress)
		}

		circularProgress.animated = false
		circularProgress.progress = 0
		circularProgress.animated = true

		gifski.convertFile(inputUrl, outputFile: outputUrl, quality: defaults["outputQuality"] as! Double)
	}
}
