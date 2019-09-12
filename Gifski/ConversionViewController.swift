import AppKit
import AVKit

final class ConversionViewController: NSViewController {

	/// If set by caller, a cancel operation will go back to the edit video controller with the given values
	var editVideoProperties: EditVideoViewController.EditVideoProperties?

	private lazy var circularProgress = with(CircularProgress(size: 160.0)) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.color = .themeColor
	}

	private lazy var timeRemainingLabel = with(Label()) {
		$0.translatesAutoresizingMaskIntoConstraints = false
		$0.isHidden = true
		$0.textColor = .secondaryLabelColor
		$0.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
	}

	private lazy var timeRemainingEstimator = TimeRemainingEstimator(label: timeRemainingLabel)

	private var conversion: Gifski.Conversion!
	private var progress: Progress?
	private var isRunning = false

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
		NSLayoutConstraint.activate([
			timeRemainingLabel.topAnchor.constraint(greaterThanOrEqualTo: circularProgress.bottomAnchor),
			timeRemainingLabel.centerXAnchor.constraint(equalTo: circularProgress.centerXAnchor),
			timeRemainingLabel.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -16.0)
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

	// TODO: Remove this when we target macOS 10.14.
	@objc
	func cancel(_ sender: Any?) {
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
		DockProgress.progressInstance = progress
		timeRemainingEstimator.progress = progress
		timeRemainingEstimator.start()

		progress?.performAsCurrent(withPendingUnitCount: 1) { [weak self] in
			Gifski.run(conversion) { result in
				guard let self = self else {
					return
				}

				do {
					let gifUrl = self.generateTempGifUrl(for: conversion.video)
					try result.get().write(to: gifUrl, options: .atomic)
					try? gifUrl.setMetadata(key: .itemCreator, value: "\(App.name) \(App.version)")
					Defaults[.successfulConversionsCount] += 1

					self.didComplete(conversion: conversion, gifUrl: gifUrl)
				} catch Gifski.Error.cancelled {
					self.cancelConversion()
				} catch {
					self.presentError(error, modalFor: self.view.window)
					self.cancelConversion()
				}
			}
		}
	}

	private func generateTempGifUrl(for videoUrl: URL) -> URL {
		let tempDirectory = FileManager.default.temporaryDirectory
		let tempName = "\(videoUrl.filenameWithoutExtension).\(FileType.gif.fileExtension)"

		return tempDirectory.appendingPathComponent(tempName, isDirectory: false)
	}

	private func cancelConversion() {
		if progress?.isCancelled == false {
			progress?.cancel()
		}

		let vc: NSViewController
		if let editVideoProperties = editVideoProperties {
			vc = EditVideoViewController(editVideoProperties: .init(
				inputUrl: editVideoProperties.inputUrl,
				asset: editVideoProperties.asset,
				videoMetadata: editVideoProperties.videoMetadata
			))
		} else {
			vc = VideoDropViewController()
		}

		stopConversion { [weak self] in
			self?.push(viewController: vc)
		}
	}

	private func didComplete(conversion: Gifski.Conversion, gifUrl: URL) {
		let conversionCompleted = ConversionCompletedViewController(conversion: conversion, gifUrl: gifUrl)
		conversionCompleted.editVideoProperties = editVideoProperties
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
