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

        // Insert code here to customize the view
        let item = self.extensionContext!.inputItems[0] as! NSExtensionItem
        if let attachments = item.attachments {
            NSLog("Attachments = %@", attachments as NSArray)
        } else {
            NSLog("No Attachments")
        }

		if let b = item.attachments?.first?.hasItemConformingToTypeIdentifier("public.file-url"), b {
			print("Rather shitty")
			item.attachments?.first?.loadFileRepresentation(forTypeIdentifier: "public.file-url") { url, error in
				if let url = url {
					DispatchQueue.main.sync {
						print(url)
						if let gifski = URL(string: "gifski://\(url.absoluteString)") {
							let request = URLRequest(url: gifski)
							self.webView.navigationDelegate = self
							self.webView.load(request)
						}

						DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
							print("Done")
							// self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
						}
					}
				}
			}
		}
    }
}

extension ShareViewController: WKNavigationDelegate {

	func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {

	}
}
