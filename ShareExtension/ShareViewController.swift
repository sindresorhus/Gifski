import Cocoa

final class ShareViewController: NSViewController {
	override var nibName: NSNib.Name? { "ShareViewController" }

    @IBOutlet private weak var errorLabel: NSTextField!
    @IBOutlet private weak var errorButtonOk: NSButton!

	// swiftlint:disable:next prohibited_super_call
	override func loadView() {
		super.loadView()

		// Make error views invisible
		errorLabel.isHidden = true
		errorButtonOk.isHidden = true

		guard let item = (self.extensionContext?.inputItems[0] as? NSExtensionItem)?.attachments?.first else {
			presentError(message: "The shared item does not contain an attachment")
			return
		}

		var typeIdentifier: String
		if item.hasItemConformingToTypeIdentifier("public.mpeg-4") {
			typeIdentifier = "public.mpeg-4"
		} else if item.hasItemConformingToTypeIdentifier("com.apple.m4v-video") {
			typeIdentifier = "com.apple.m4v-video"
		} else if item.hasItemConformingToTypeIdentifier("com.apple.quicktime-movie") {
			typeIdentifier = "com.apple.quicktime-movie"
		} else {
			presentError(message: "The shared item is not in a valid video format")
			return
		}

		item.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
			guard let url = url else {
				self.presentError(message: error?.localizedDescription ?? "Unknown error")
				return
			}

			let shareUrl = "\(url.lastPathComponent)"
			let appIdentifierPrefix = Bundle.main.infoDictionary!["AppIdentifierPrefix"] as! String

			guard let appGroupShareVideUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "\(appIdentifierPrefix).gifski_video_share_group")?.appendingPathComponent(shareUrl) else {
				self.presentError(message: "Could not share video with the main app")
				return
			}

			try? FileManager.default.removeItem(at: appGroupShareVideUrl)
			do {
				try FileManager.default.copyItem(at: url, to: appGroupShareVideUrl)
			} catch {
				self.presentError(message: error.localizedDescription)
				return
			}

			guard let gifski = self.createMainAppUrl(
				queryItems: [URLQueryItem(name: "path", value: shareUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)]
			) else {
				self.presentError(message: "Could not share video with the main app")
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

	private func createMainAppUrl(queryItems: [URLQueryItem] = []) -> URL? {
		var components = URLComponents()
		components.scheme = "gifski"
		components.host = "shareExtension"
		components.queryItems = queryItems

		return components.url
	}

    // MARK: - Actions

    @IBAction private func errorButtonOkClicked(_ sender: Any) {
		self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
