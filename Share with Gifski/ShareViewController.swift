//
//  ShareViewController.swift
//  Share with Gifski
//
//  Created by Koray Koska on 12.09.19.
//  Copyright © 2019 Sindre Sorhus. All rights reserved.
//

import Cocoa
import WebKit

class ShareViewController: NSViewController {

    override var nibName: NSNib.Name? {
        return NSNib.Name("ShareViewController")
    }

    override func loadView() {
		super.loadView()

		guard let item = (self.extensionContext?.inputItems[0] as? NSExtensionItem)?.attachments?.first else {
			errorOpenMainApp()
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
			errorOpenMainApp()
			return
		}

		item.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
			guard let url = url else {
				self.errorOpenMainApp()
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

	private func errorOpenMainApp() {
		let gifski = URL(string: "gifski://shareExtension?error=true")!
		NSWorkspace.shared.open(gifski)
		self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
	}
}
