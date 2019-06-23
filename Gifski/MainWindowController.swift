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

	private lazy var timeRemainingLabel = with(Label()) {
		$0.isHidden = true
		$0.textColor = .secondaryLabelColor
		$0.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
	}

	private lazy var conversionCompletedView = with(ConversionCompletedView()) {
		$0.isHidden = true
	}

//	private var accessoryViewController: SavePanelAccessoryViewController!
//	private var choosenDimensions: CGSize?
//	private var choosenFrameRate: Int?

//	private var outUrl: URL!

	var isRunning: Bool = false //{
//		didSet {
//			videoDropView.isHidden = isRunning
//
//			if let progress = progress, !isRunning {
//				circularProgress.fadeOut(delay: 1) {
//					self.circularProgress.resetProgress()
//					DockProgress.resetProgress()
//
//					if progress.isFinished {
//						self.conversionCompletedView.fileUrl = self.outUrl
//						self.conversionCompletedView.show()
//						self.videoDropView.isDropLabelHidden = true
//					} else {
//						self.videoDropView.isHidden = false
//						self.videoDropView.fadeInVideoDropLabel()
//					}
//				}
//			} else {
//				circularProgress.isHidden = false
//				videoDropView.isDropLabelHidden = true
//				conversionCompletedView.isHidden = true
//			}
//		}
//	}

	convenience init() {
		let window = NSWindow.centeredWindow(size: .zero)
		window.contentViewController = DropVideoViewController()
		window.centerNatural()
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

//		view?.addSubview(circularProgress)
//		view?.addSubview(timeRemainingLabel)
//		view?.addSubview(conversionCompletedView, positioned: .above, relativeTo: nil)

//		setupTimeRemainingLabel()

		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: false)

		DockProgress.style = .circle(radius: 55, color: .themeColor)
	}

	/// Gets called when the Esc key is pressed.
	/// Reference: https://stackoverflow.com/a/42440020
	@objc
	func cancel(_ sender: Any?) {
//		cancelConversion()
	}

	private var progress: Progress?
	private lazy var timeRemainingEstimator = TimeRemainingEstimator(label: timeRemainingLabel)

//	func startConversion(inputUrl: URL, outputUrl: URL) {
//		guard !isRunning else {
//			return
//		}
//
//		outUrl = outputUrl
//
//		isRunning = true
//
//		progress = Progress(totalUnitCount: 1)
//		progress?.publish()
//
//		circularProgress.progressInstance = progress
//		DockProgress.progressInstance = progress
//		timeRemainingEstimator.progress = progress
//		timeRemainingEstimator.start()
//
//		progress?.performAsCurrent(withPendingUnitCount: 1) {
//			let conversion = Gifski.Conversion(
//				input: inputUrl,
//				output: outputUrl,
//				quality: defaults[.outputQuality],
//				dimensions: self.choosenDimensions,
//				frameRate: self.choosenFrameRate
//			)
//
//			Gifski.run(conversion) { error in
//				self.progress?.unpublish()
//				self.isRunning = false
//
//				if let error = error {
//					self.progress?.cancel()
//
//					switch error {
//					case .cancelled:
//						break
//					default:
//						self.presentError(error, modalFor: self.window)
//					}
//
//					return
//				}
//
//				defaults[.successfulConversionsCount] += 1
//				if #available(macOS 10.14, *), defaults[.successfulConversionsCount] == 5 {
//					SKStoreReviewController.requestReview()
//				}
//
//				if #available(macOS 10.14, *), !NSApp.isActive || self.window?.isVisible == false {
//					let notification = UNMutableNotificationContent()
//					notification.title = "Conversion Completed"
//					notification.subtitle = outputUrl.filename
//					let request = UNNotificationRequest(identifier: "conversionCompleted", content: notification, trigger: nil)
//					UNUserNotificationCenter.current().add(request)
//				}
//			}
//		}
//	}

//	private func cancelConversion() {
//		progress?.cancel()
//	}

	@objc
	func open(_ sender: AnyObject) {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = false
		panel.canCreateDirectories = false
		panel.allowedFileTypes = System.supportedVideoTypes

		panel.beginSheetModal(for: window!) {
			if $0 == .OK {
//				self.convert(panel.url!)
			}
		}
	}

//	private func setupTimeRemainingLabel() {
//		guard let view = view else {
//			return
//		}
//
//		timeRemainingLabel.translatesAutoresizingMaskIntoConstraints = false
//
//		NSLayoutConstraint.activate([
//			timeRemainingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//			timeRemainingLabel.topAnchor.constraint(equalTo: circularProgress.bottomAnchor)
//		])
//	}
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
