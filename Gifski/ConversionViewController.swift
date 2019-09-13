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

	private var progress: Progress?
	private var isRunning = false
	private var source: GifSource?

	convenience init(source: GifSource) {
		self.init()
		
		self.source = source
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

		start(source: source)
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

	private func start(source: GifSource?) {
		guard !isRunning, let source = source else {
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
			
			let gifUrl: URL
			switch source {
				case .conversionNeeded(let conversion):
					gifUrl = self.generateTempGifUrl(for: conversion!.video)
					break
				case .gifDataAvailable(_, let video):
					gifUrl = self.generateTempGifUrl(for: video)
					break
			}
			switch source {
				case .conversionNeeded(let conversion):
					Gifski.run(conversion!, completionHandler: { result in
						do {
							try result.get().write(to: gifUrl, options: .atomic)
						} catch Gifski.Error.cancelled {
							self.cancelConversion()
						} catch {
							self.presentError(error, modalFor: self.view.window)
							self.cancelConversion()
						}
						
						defaults[.successfulConversionsCount] += 1

						self.didComplete(gifUrl: gifUrl)
					})
					break
				case .gifDataAvailable(let gifData, _):
					do {
						try gifData.write(to: gifUrl, options: .atomic)
						self.didComplete(gifUrl: gifUrl)
					} catch {
						presentError(error, modalFor: view.window)
						cancelConversion()
					}
					break
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

	private func didComplete(gifUrl: URL) {
		let inputUrl: URL
		
		switch self.source {
			case .conversionNeeded(let conversion):
				inputUrl = conversion!.video
				break
			case .gifDataAvailable(_, let url):
				inputUrl = url
				break
			case .none:
				return
		}
		
		let conversionCompleted = ConversionCompletedViewController(gifUrl: gifUrl, inputUrl: inputUrl)
		
		try? gifUrl.setMetadata(key: .itemCreator, value: "\(App.name) \(App.version)")
		defaults[.successfulConversionsCount] += 1
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


enum GifSource { // I have no Idea what else to call it
    case conversionNeeded(Gifski.Conversion!)
	// Data and Video
    case gifDataAvailable(Data, URL)
}
