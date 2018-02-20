import Cocoa
import ProgressKit

private let defaults = UserDefaults.standard

extension NSColor {
	static let appTheme = NSColor(named: NSColor.Name("Theme"))!
}

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	@IBOutlet private weak var window: NSWindow!
	var videoDropView: VideoDropView!
	let gifski = Gifski()

	lazy var circularProgress: CircularProgressView = {
		let size: CGFloat = 160
		let view = CircularProgressView(frame: CGRect(widthHeight: size))
		view.centerInWindow(window)
		view.foreground = .appTheme
		view.strokeWidth = 2
		view.percentLabelLayer.setAutomaticContentsScale()
		view.percentLabelLayer.implicitAnimations = false
		view.layer?.backgroundColor = .clear
		view.isHidden = true
		return view
	}()

	var hasFinishedLaunching = false
	var urlsToConvertOnLaunch: URL!
	var choosenDimensions: CGSize!

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

		view.addSubview(circularProgress)

		videoDropView = VideoDropView(frame: view.frame)
		videoDropView.dropText = "Drop a Video to Convert to GIF"
		videoDropView.onComplete = { url in
			self.convert(url.first!)
		}
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
			circularProgress.fadeOut(delay: 1) {
				self.isRunning = false
			}
		}
	}

	func convert(_ inputUrl: URL) {
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

		gifski.convertFile(
			inputUrl,
			outputFile: outputUrl,
			quality: defaults["outputQuality"] as! Double,
			dimensions: choosenDimensions
		)
	}
}
