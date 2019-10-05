//
//  ReplacePresentationAnimator.swift
//  Gifski
//
//  Created by Sergey Kuryanov on 05/10/2019.
//  Copyright © 2019 Sindre Sorhus. All rights reserved.
//

import Cocoa

class ReplacePresentationAnimator: NSObject, NSViewControllerPresentationAnimator {
	func animatePresentation(of viewController: NSViewController, from fromViewController: NSViewController) {
		animateTransition(of: viewController, from: fromViewController)
	}

	func animateDismissal(of viewController: NSViewController, from fromViewController: NSViewController) {
		animateTransition(of: viewController, from: fromViewController)
	}

	private func animateTransition(of viewController: NSViewController, from fromViewController: NSViewController) {
		guard let window = fromViewController.view.window else {
			return
		}

		var newWindowFrame = CGRect(origin: .zero, size: viewController.view.frame.size)
		newWindowFrame.center = window.frame.center

		viewController.view.alphaValue = 0

		NSAnimationContext.runAnimationGroup({ _ in
			fromViewController.view.animator().alphaValue = 0
			window.contentViewController = nil
			window.animator().setFrame(newWindowFrame, display: true)
		}, completionHandler: {
			window.contentViewController = viewController
			viewController.view.animator().alphaValue = 1
		})
	}
}
