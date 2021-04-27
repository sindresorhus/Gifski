import AppKit
import CircularProgress
import DockProgress
import Defaults

final class ConversionViewController: NSViewController {
	private lazy var circularProgress = with(CircularProgress(size: 160.0)) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.color = .progressCircleColor
		$0.lineWidth = 3
	}

	private lazy var timeRemainingLabel = with(Label()) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.isHidden = true
		$0.textColor = .secondaryLabelColor
		$0.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
	}

	private lazy var timeRemainingEstimator = TimeRemainingEstimator(label: timeRemainingLabel)

	private var conversion: Gifski.Conversion!
	private var progress: Progress?
	private var isRunning = false
	private let gifski = Gifski()

	convenience init(conversion: Gifski.Conversion) {
		self.init()

		self.conversion = conversion
	}

	override func loadView() {
		let wrapper = NSView(frame: Constants.defaultWindowSize.cgRect)
		wrapper.translatesAutoresizingMaskIntoConstraints = false
		wrapper.addSubview(circularProgress)
		wrapper.addSubview(timeRemainingLabel)

		circularProgress.constrain(to: CGSize(widthHeight: circularProgress.frame.width))
		circularProgress.center(inView: wrapper)
		timeRemainingLabel.centerX(inView: circularProgress)
		timeRemainingLabel.constrainToEdges(verticalEdge: .bottom, view: wrapper, padding: -16)
		NSLayoutConstraint.activate([
			timeRemainingLabel.topAnchor.constraint(greaterThanOrEqualTo: circularProgress.bottomAnchor)
		])

		view = wrapper
	}

	override func viewDidAppear() {
		super.viewDidAppear()

		view.window?.makeFirstResponder(self)

		start(conversion: conversion)
	}

	/// Gets called when the Esc key is pressed.
	override func cancelOperation(_ sender: Any?) {
		cancelConversion()
	}

	private func start(conversion: Gifski.Conversion) {
		guard !isRunning else {
			return
		}

		isRunning = true

		progress = Progress(totalUnitCount: 1)
		progress?.publish()

		circularProgress.progressInstance = progress
		DockProgress.style = .squircle(color: SSApp.isDarkMode ? .white.withAlphaComponent(0.7) : .progressCircleColor)
		DockProgress.progressInstance = progress
		timeRemainingEstimator.progress = progress
		timeRemainingEstimator.start()

		progress?.performAsCurrent(withPendingUnitCount: 1) { [weak self] in
			guard let self = self else {
				return
			}

			gifski.run(conversion, isEstimation: false) { result in
				do {
					let gifUrl = try self.generateTemporaryGifUrl(for: conversion.video)
					try result.get().write(to: gifUrl, options: .atomic)
					try? gifUrl.setMetadata(key: .itemCreator, value: "\(SSApp.name) \(SSApp.version)")
					self.didComplete(conversion: conversion, gifUrl: gifUrl)
				} catch Gifski.Error.cancelled {
					self.cancelConversion()
				} catch {
					error.presentAsModalSheet(for: self.view.window)
					self.cancelConversion()
				}
			}
		}
	}

	private func generateTemporaryGifUrl(for videoUrl: URL) throws -> URL {
		let temporaryDirectory = try FileManager.default.url(
			for: .itemReplacementDirectory,
			in: .userDomainMask,
			// We force it to be on the main disk as we don't want the generated GIF to disappear, for example, if the source URL is on a USB drive, which could be ejected at any time.
			appropriateFor: FileManager.default.homeDirectoryForCurrentUser,
			create: true
		)

		let filename = "\(videoUrl.filenameWithoutExtension).\(FileType.gif.fileExtension)"

		return temporaryDirectory.appendingPathComponent(filename, isDirectory: false)
	}

	private func cancelConversion() {
		if progress?.isCancelled == false {
			progress?.cancel()
		}

		stopConversion { [weak self] in
			// It's safe to force-unwrap as there's no scenario where it will be nil.
			let viewController = AppDelegate.shared.previousEditViewController!
			viewController.isConverting = false

			self?.push(viewController: viewController)
		}
	}

	private func didComplete(conversion: Gifski.Conversion, gifUrl: URL) {
		let conversionCompleted = ConversionCompletedViewController(conversion: conversion, gifUrl: gifUrl)
		stopConversion { [weak self] in
			self?.push(viewController: conversionCompleted)
		}
	}

	private func stopConversion(_ completion: (() -> Void)? = nil) {
		isRunning = false
		DockProgress.resetProgress()

		circularProgress.fadeOut(delay: 0.5) {
			completion?()
		}
	}
}
