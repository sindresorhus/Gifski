import Cocoa
import AVFoundation
import UserNotifications
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
		$0.textColor = .secondaryLabelColor
		$0.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
	}

	private lazy var conversionCompletedView = with(ConversionCompletedView()) {
		$0.isHidden = true
	}

	private var accessoryViewController: SavePanelAccessoryViewController!
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

					if progress.isFinished, !progress.isCancelled {
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
		Crashlytics.record(
			key: "Does input file exist",
			value: inputUrl.exists
		)
		Crashlytics.record(
			key: "Is input file reachable",
			value: try? inputUrl.checkResourceIsReachable()
		)
		Crashlytics.record(
			key: "Is input file readable",
			value: inputUrl.isReadable
		)

		// This is very unlikely to happen. We have a lot of file type filters in place, so the only way this can happen is if the user right-clicks a non-video in Finder, chooses "Open With", then "Other…", chooses "All Applications", and then selects Gifski. Yet, some people are doing this…
		guard inputUrl.isVideo else {
			NSAlert.showModal(
				for: window,
				message: "The selected file cannot be converted because it's not a video.",
				informativeText: "Try again with a video file, usually with the file extension “mp4” or “mov”."
			)
			return
		}

		let asset = AVURLAsset(url: inputUrl)

		Crashlytics.record(key: "AVAsset debug info", value: asset.debugInfo)

		guard asset.videoCodec != .appleAnimation else {
			NSAlert.showModal(
				for: window,
				message: "The QuickTime Animation format is not supported.",
				informativeText: "Re-export or convert your video to ProRes 4444 XQ instead. It's more efficient, more widely supported, and like QuickTime Animation, it also supports alpha channel. To convert an existing video, open it in QuickTime Player, which will automatically convert it, and then save it."
			)
			return
		}

		if asset.hasAudio && !asset.hasVideo {
			NSAlert.showModal(
				for: window,
				message: "Audio files are not supported.",
				informativeText: "Gifski converts video files but the provided file is audio-only. Please provide a file that contains video."
			)

			return
		}

		// We already specify the UTIs we support, so this can only happen on invalid video files or unsupported codecs.
		guard asset.isVideoDecodable else {
			NSAlert.showModalAndReportToCrashlytics(
				for: window,
				message: "The video file is not supported.",
				informativeText: "Please open an issue on https://github.com/sindresorhus/Gifski or email sindresorhus@gmail.com. ZIP the video and attach it.\n\nInclude this info:",
				debugInfo: asset.debugInfo
			)

			return
		}

		guard let videoMetadata = asset.videoMetadata else {
			NSAlert.showModalAndReportToCrashlytics(
				for: window,
				message: "The video metadata is not readable.",
				informativeText: "Please open an issue on https://github.com/sindresorhus/Gifski or email sindresorhus@gmail.com. ZIP the video and attach it.\n\nInclude this info:",
				debugInfo: asset.debugInfo
			)

			return
		}

		guard
			let dimensions = asset.dimensions,
			dimensions.width > 10,
			dimensions.height > 10
		else {
			NSAlert.showModalAndReportToCrashlytics(
				for: window,
				message: "The video dimensions must be at least 10×10.",
				informativeText: "The dimensions of your video are \(asset.dimensions?.formatted ?? "0×0").\n\nIf you think this error is a mistake, please open an issue on https://github.com/sindresorhus/Gifski or email sindresorhus@gmail.com. ZIP the video and attach it.\n\nInclude this info:",
				debugInfo: asset.debugInfo
			)

			return
		}

		let panel = NSSavePanel()
		panel.canCreateDirectories = true
		panel.allowedFileTypes = [FileType.gif.identifier]
		panel.directoryURL = inputUrl.directoryURL
		panel.nameFieldStringValue = inputUrl.filenameWithoutExtension
		panel.prompt = "Convert"
		panel.message = "Choose where to save the GIF"

		accessoryViewController = SavePanelAccessoryViewController()
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

			self.accessoryViewController = nil
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
				video: inputUrl,
				quality: defaults[.outputQuality],
				dimensions: self.choosenDimensions,
				frameRate: self.choosenFrameRate
			)

			Gifski.run(conversion) { result in
				do {
					try result.get().write(to: outputUrl, options: [.atomic])
				} catch Gifski.Error.cancelled {
					self.progress?.cancel()
				} catch {
					self.progress?.cancel()
					self.presentError(error, modalFor: self.window)
				}

				try? inputUrl.setMetadata(key: .itemCreator, value: "\(App.name) \(App.versionWithBuild)")
				self.progress?.unpublish()
				self.isRunning = false

				defaults[.successfulConversionsCount] += 1
				if #available(macOS 10.14, *), defaults[.successfulConversionsCount] == 5 {
					SKStoreReviewController.requestReview()
				}

				if #available(macOS 10.14, *), !NSApp.isActive || self.window?.isVisible == false {
					let notification = UNMutableNotificationContent()
					notification.title = "Conversion Completed"
					notification.subtitle = outputUrl.filename
					let request = UNNotificationRequest(identifier: "conversionCompleted", content: notification, trigger: nil)
					UNUserNotificationCenter.current().add(request)
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
			return true
		}
	}
}
