//
//  SavePanelLockView.swift
//  Gifski
//
//  Created by Shams al-Din Shakuntala on 1/16/19.
//  Copyright © 2019 Sindre Sorhus. All rights reserved.
//

import Cocoa

class SavePanelLockView: NSView {
	private var displayAsLocked: Bool = true
	@IBOutlet private var lockUnlockButton: NSButton!
	@IBOutlet private var linkedLinesView: NSView!
	@IBOutlet private var lockImageView: NSImageView!

	var locked: Bool {
		set {
			displayAsLocked = newValue
			refreshLockStatus()
		}
		get {
			return displayAsLocked
		}
	}

	func refreshLockStatus() {
		if displayAsLocked {
			linkedLinesView.isHidden = false
			lockImageView.image = NSImage(named: NSImage.lockLockedTemplateName)
		} else {
			linkedLinesView.isHidden = true
			lockImageView.image = NSImage(named: NSImage.lockUnlockedTemplateName)
		}
	}
}
