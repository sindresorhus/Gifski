import AppKit

final class ConversionViewController: NSViewController {
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
	private var gifData: Data?	
	private var progress: Progress?
	private var isRunning = false

	convenience init(_ conversion: Gifski.Conversion, _ gifData: Data?) {
		self.init()

		self.gifData = gifData
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

		start(gifData: gifData, conversion: conversion)
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

	private func start(gifData: Data?, conversion: Gifski.Conversion) {
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
			guard let self = self else {
				return
			}
			let gifUrl = self.generateTempGifUrl(for: conversion.video)
			if let gifData = gifData {
				do {
					try gifData.write(to: gifUrl, options: .atomic)

					try? gifUrl.setMetadata(key: .itemCreator, value: "\(App.name) \(App.version)")
					defaults[.successfulConversionsCount] += 1

					self.didComplete(conversion: conversion, gifUrl: gifUrl)
				} catch Gifski.Error.cancelled {
					cancelConversion()
				} catch {
					presentError(error, modalFor: view.window)
					cancelConversion()
				}
			} else {
				Gifski.run(conversion) { result in
					do {
						try result.get().write(to: gifUrl, options: .atomic)
					} catch Gifski.Error.cancelled {
						self.cancelConversion()
					} catch {
						self.presentError(error, modalFor: self.view.window)
						self.cancelConversion()
					}
					try? gifUrl.setMetadata(key: .itemCreator, value: "\(App.name) \(App.version)")
					defaults[.successfulConversionsCount] += 1

					self.didComplete(conversion: conversion, gifUrl: gifUrl)
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

		let videoDropController = VideoDropViewController()
		stopConversion { [weak self] in
			self?.push(viewController: videoDropController)
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
