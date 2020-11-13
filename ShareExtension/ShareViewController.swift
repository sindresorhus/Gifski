import Cocoa

final class ShareViewController: NSViewController {
	override var nibName: NSNib.Name? { "ShareViewController" }

	@IBOutlet private var errorLabel: NSTextField!
	@IBOutlet private var errorButtonOk: NSButton!

	// swiftlint:disable:next prohibited_super_call
	override func loadView() {
		super.loadView()

		// Make error views invisible
		errorLabel.isHidden = true
		errorButtonOk.isHidden = true

		guard
			let item = extensionContext?.attachments.first
		else {
			presentError(message: "The shared item does not contain an attachment.")
			return
		}

		// TODO: Use `UTType` here when targeting macOS 11.
		var typeIdentifier: String
		if item.hasItemConformingToTypeIdentifier("public.mpeg-4") {
			typeIdentifier = "public.mpeg-4"
		} else if item.hasItemConformingToTypeIdentifier("com.apple.m4v-video") {
			typeIdentifier = "com.apple.m4v-video"
		} else if item.hasItemConformingToTypeIdentifier("com.apple.quicktime-movie") {
			typeIdentifier = "com.apple.quicktime-movie"
		} else {
			presentError(message: "The shared item is not in a supported video format.")
			return
		}

		item.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, error in
			guard let self = self else {
				return
			}

			guard let url = url else {
				self.presentError(message: error?.localizedDescription ?? "Unknown error")
				return
			}

			let shareUrl = url.lastPathComponent

			guard
				let appGroupShareVideoUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.videoShareGroupIdentifier)?.appendingPathComponent(shareUrl, isDirectory: false)
			else {
				self.presentError(message: "Could not share the video with the main app.")
				return
			}

			try? FileManager.default.removeItem(at: appGroupShareVideoUrl)

			do {
				try FileManager.default.copyItem(at: url, to: appGroupShareVideoUrl)
			} catch {
				self.presentError(message: error.localizedDescription)
				return
			}

			guard
				let gifski = self.createMainAppUrl(
					queryItems: [
						URLQueryItem(name: "path", value: shareUrl)
					]
				)
			else {
				self.presentError(message: "Could not share the video with the main app.")
				return
			}

			DispatchQueue.main.sync {
				NSWorkspace.shared.open(gifski)
				self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
			}
		}
	}

	private func presentError(message: String) {
		errorLabel.isHidden = false
		errorButtonOk.isHidden = false
		errorLabel.stringValue = message
	}

	private func createMainAppUrl(queryItems: [URLQueryItem]) -> URL? {
		var components = URLComponents()
		components.scheme = "gifski"
		components.host = "shareExtension"
		components.queryItems = queryItems
		return components.url
	}

	// MARK: - Actions

	@IBAction
	private func errorButtonOkClicked(_ sender: Any) {
		extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
	}
}
