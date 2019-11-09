import Cocoa

final class ShareViewController: NSViewController {
	override var nibName: NSNib.Name? { NSNib.Name("ShareViewController") }

	override func loadView() {
		super.loadView()

		guard let item = (self.extensionContext?.inputItems[0] as? NSExtensionItem)?.attachments?.first else {
			errorOpenMainApp(message: "Shared item does not contain an attachment")
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
			errorOpenMainApp(message: "Shared item is not in a valid video format")
			return
		}

		item.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
			guard let url = url else {
				self.errorOpenMainApp(message: error?.localizedDescription ?? "Unknown error")
				return
			}

			let shareUrl = "\(url.lastPathComponent)"
			let appIdentifierPrefix = Bundle.main.infoDictionary!["AppIdentifierPrefix"] as! String
			let appGroupShareVideUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "\(appIdentifierPrefix).gifski_video_share_group")?.appendingPathComponent(shareUrl)

			try? FileManager.default.removeItem(at: appGroupShareVideUrl!)
			try! FileManager.default.copyItem(at: url, to: appGroupShareVideUrl!)

			let gifski = URL(string: "gifski://shareExtension?path=\(shareUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)")!

			DispatchQueue.main.sync {
				NSWorkspace.shared.open(gifski)
				self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
			}
		}
	}

	private func errorOpenMainApp(message: String) {
		let gifski = URL(string: "gifski://shareExtension?error=\(message)")!
		NSWorkspace.shared.open(gifski)
		self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
	}
}
