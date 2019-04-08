import Cocoa
import AVFoundation
import StoreKit
import Crashlytics

final class MainWindowController: NSWindowController {
	private lazy var circularProgress = with(CircularProgress(size: 160)) {
		$0.color = .themeColor
		$0.isHidden = true
		$0.centerInWindow(window)
	}

	private lazy var videoDropView = with(VideoDropView()) {
		$0.dropText = "Drop a Video to Convert to GIF"

		let this = $0
		$0.onComplete = { url in
			NSApp.activate(ignoringOtherApps: true)
			self.convert(url.first!)
		}
	}

	private lazy var timeRemainingLabel = with(Label()) {
		$0.isHidden = true
		$0.textColor = NSColor.secondaryLabelColor
		$0.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
	}

	private lazy var conversionCompletedView = with(ConversionCompletedView()) {
		$0.isHidden = true
	}

	private var choosenDimensions: CGSize?
	private var choosenFrameRate: Int?

	private var outUrl: URL!

	var isRunning: Bool = false {
		didSet {
			videoDropView.isHidden = isRunning

			if let progress = progress, !isRunning {
				circularProgress.fadeOut(delay: 1) {
					self.circularProgress.resetProgress()
					DockProgress.resetProgress()

					if progress.isFinished {
						self.conversionCompletedView.fileUrl = self.outUrl
						self.conversionCompletedView.show()
						self.videoDropView.isDropLabelHidden = true
					} else {
						self.videoDropView.isHidden = false
						self.videoDropView.fadeInVideoDropLabel()
					}
				}
			} else {
				circularProgress.isHidden = false
				videoDropView.isDropLabelHidden = true
				conversionCompletedView.isHidden = true
			}
		}
	}

	convenience init() {
		let window = NSWindow.centeredWindow(size: CGSize(width: 360, height: 240))
		self.init(window: window)

		with(window) {
			$0.delegate = self
			$0.titleVisibility = .hidden
			$0.styleMask = [
				.titled,
				.closable,
				.miniaturizable,
				.fullSizeContentView
			]
			$0.tabbingMode = .disallowed
			$0.collectionBehavior = .fullScreenNone
			$0.titlebarAppearsTransparent = true
			$0.isMovableByWindowBackground = true
			$0.isRestorable = false
			$0.makeVibrant()
		}

		view?.addSubview(circularProgress)
		view?.addSubview(timeRemainingLabel)
		view?.addSubview(videoDropView, positioned: .above, relativeTo: nil)
		view?.addSubview(conversionCompletedView, positioned: .above, relativeTo: nil)

		setupTimeRemainingLabel()

		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: false)

		DockProgress.style = .circle(radius: 55, color: .themeColor)
	}

	/// Gets called when the Esc key is pressed.
	/// Reference: https://stackoverflow.com/a/42440020
	@objc
	func cancel(_ sender: Any?) {
		cancelConversion()
	}

	func convert(_ inputUrl: URL) {
		let asset = AVURLAsset(url: inputUrl)

		guard asset.videoCodec != "rle" else {
			NSAlert.showModal(
				for: window,
				title: "QuickTime Animation format not supported",
				message: "Re-export or convert your video to ProRes 4444 XQ instead. It's more efficient, more widely supported, and like QuickTime Animation, it also supports alpha channel. To convert an existing video, just open it in QuickTime Player (which will convert it) and then save it."
			)
			return
		}

		// We already specify the UTIs we support, so this can only happen on invalid video files or unsupported codecs.
		guard asset.isVideoDecodable else {
			NSAlert.showModal(
				for: window,
				title: "Video file not supported",
				message: "The video file you tried to convert could not be read. Please open an issue on https://github.com/sindresorhus/gifski-app. ZIP the video and attach it to the issue.\n\nInclude this info:\n\(asset.debugInfo)"
			)

			Crashlytics.sharedInstance().recordErrorMessage("Video file not supported: \(asset.debugInfo)")
			return
		}

		guard let videoMetadata = asset.videoMetadata else {
			NSAlert.showModal(
				for: window,
				title: "Video metadata not readable",
				message: "The metadata of the video could not be read. Please open an issue on https://github.com/sindresorhus/gifski-app. ZIP the video and attach it to the issue.\n\nInclude this info:\n\(asset.debugInfo)"
			)

			Crashlytics.sharedInstance().recordErrorMessage("Video metadata not readable: \(asset.debugInfo)")
			return
		}

		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		panel.allowedFileTypes = [FileType.gif.identifier]
		panel.directoryURL = inputUrl.directoryURL
		panel.nameFieldStringValue = inputUrl.filenameWithoutExtension
		panel.prompt = "Convert"
		panel.message = "Choose where to save the GIF"

		let accessoryViewController = SavePanelAccessoryViewController()
		accessoryViewController.inputUrl = inputUrl
		accessoryViewController.videoMetadata = videoMetadata

		accessoryViewController.onDimensionChange = { dimension in
			self.choosenDimensions = dimension
		}

		accessoryViewController.onFramerateChange = { frameRate in
			self.choosenFrameRate = frameRate
		}

		panel.accessoryView = accessoryViewController.view

		panel.beginSheetModal(for: window!) {
			if $0 == .OK {
				self.startConversion(inputUrl: inputUrl, outputUrl: panel.url!)
			}
		}
	}

	private var progress: Progress?
	private lazy var timeRemainingEstimator = TimeRemainingEstimator(label: timeRemainingLabel)

	func startConversion(inputUrl: URL, outputUrl: URL) {
		guard !isRunning else {
			return
		}

		outUrl = outputUrl

		isRunning = true

		progress = Progress(totalUnitCount: 1)
		progress?.publish()

		circularProgress.progressInstance = progress
		DockProgress.progressInstance = progress
		timeRemainingEstimator.progress = progress
		timeRemainingEstimator.start()

		progress?.performAsCurrent(withPendingUnitCount: 1) {
			let conversion = Gifski.Conversion(
				input: inputUrl,
				output: outputUrl,
				quality: defaults[.outputQuality],
				dimensions: self.choosenDimensions,
				frameRate: self.choosenFrameRate
			)

			Gifski.run(conversion) { error in
				self.progress?.unpublish()
				self.isRunning = false

				if let error = error {
					self.progress?.cancel()

					switch error {
					case .cancelled:
						break
					default:
						self.presentError(error, modalFor: self.window)
					}

					return
				}

				defaults[.successfulConversionsCount] += 1
				if #available(macOS 10.14, *), defaults[.successfulConversionsCount] == 5 {
					SKStoreReviewController.requestReview()
				}
			}
		}
	}

	private func cancelConversion() {
		progress?.cancel()
	}

	@objc
	func open(_ sender: AnyObject) {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = false
		panel.canCreateDirectories = false
		panel.allowedFileTypes = System.supportedVideoTypes

		panel.beginSheetModal(for: window!) {
			if $0 == .OK {
				self.convert(panel.url!)
			}
		}
	}

	private func setupTimeRemainingLabel() {
		guard let view = view else {
			return
		}

		timeRemainingLabel.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			timeRemainingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			timeRemainingLabel.topAnchor.constraint(equalTo: circularProgress.bottomAnchor)
		])
	}
}

extension MainWindowController: NSMenuItemValidation {
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		switch menuItem.action {
		case #selector(open)?:
			return !isRunning
		default:
			return validateMenuItem(menuItem)
		}
	}
}
