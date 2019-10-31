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

    @IBOutlet private var webView: WKWebView!

    override var nibName: NSNib.Name? {
        return NSNib.Name("ShareViewController")
    }

    override func loadView() {
		super.loadView()

		// Show loading screen on webView while we are copying the video
		let loadingHtml = try! String(contentsOf: Bundle.main.url(forResource: "loadingHtml", withExtension: "html")!)
		webView.loadHTMLString(loadingHtml, baseURL: nil)

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

		item.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
			DispatchQueue.main.sync {
				if let url = url {
					let shareUrl = "\(url.lastPathComponent)"

					let appIdentifierPrefix = Bundle.main.infoDictionary!["AppIdentifierPrefix"] as! String
					let appGroupShareVideUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "\(appIdentifierPrefix).gifski_video_share_group")?.appendingPathComponent(shareUrl)

					try? FileManager.default.removeItem(at: appGroupShareVideUrl!)
					try! FileManager.default.copyItem(at: url, to: appGroupShareVideUrl!)

					if let gifski = URL(string: "gifski://\(shareUrl.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!)?shareExtension=true") {
						let request = URLRequest(url: gifski)
						self.webView.navigationDelegate = self
						self.webView.load(request)
					}

					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
						self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
					}
				} else if error != nil {
					self.errorOpenMainApp()
				}
			}
		}
    }

	private func errorOpenMainApp() {
		if let gifski = URL(string: "gifski://error?shareExtension=true") {
			let request = URLRequest(url: gifski)
			self.webView.navigationDelegate = self
			self.webView.load(request)
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
		}
	}
}

extension ShareViewController: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {

	}
}
