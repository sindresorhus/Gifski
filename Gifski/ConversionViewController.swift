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
	private var progress: Progress?
	private var isRunning = false

	convenience init(conversion: Gifski.Conversion) {
		self.init()

		self.conversion = conversion
	}

	override func loadView() {
		let wrapper = NSView(frame: CGRect(origin: .zero, size: Constants.defaultWindowSize))
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

	override func viewDidLoad() {
		super.viewDidLoad()

		start(conversion: conversion)
	}

	/// Gets called when the Esc key is pressed.
	/// Reference: https://stackoverflow.com/a/42440020
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

		progress?.performAsCurrent(withPendingUnitCount: 1) {
			Gifski.run(conversion) { result in
				do {
					let gifUrl = self.generateTempGifUrl(for: conversion.video)
					try result.get().write(to: gifUrl, options: .atomic)
					try? gifUrl.setMetadata(key: .itemCreator, value: "\(App.name) \(App.version)")
					defaults[.successfulConversionsCount] += 1

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
		progress?.cancel()
		progress?.unpublish()

		let dropView = VideoDropViewController()
		circularProgress.fadeOut(delay: 1.0) {
			self.push(viewController: dropView)
		}
	}

	private func didComplete(conversion: Gifski.Conversion, gifUrl: URL) {
		let conversionCompleted = ConversionCompletedViewController(conversion: conversion, gifUrl: gifUrl)
		isRunning = false
		progress?.unpublish()

		circularProgress.fadeOut(delay: 1.0) {
			self.circularProgress.resetProgress()
			DockProgress.resetProgress()
			self.push(viewController: conversionCompleted)
		}
	}
}
