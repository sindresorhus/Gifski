import AppKit

final class MenuPopUpButton: NSPopUpButton, NSMenuDelegate {
	override var acceptsFirstResponder: Bool {
		return true
	}

	/// `selectedIndex` is nil when the user didn't select any index this time (probably quit)
	var onMenuDidCloseAction: ((_ selectedIndex: Int?) -> Void)?
	var onMenuWillOpenAction: (() -> Void)?

	/// If true it will regain focus once the menu has been touched
	var shouldFocus = true

	private var currentlySelectedIndex: Int?

	override func awakeFromNib() {
		super.awakeFromNib()
		menu?.delegate = self
	}

	func menuDidClose(_ menu: NSMenu) {
		if shouldFocus {
			window?.makeFirstResponder(self)
		}
		let selectedIndex: Int? = currentlySelectedIndex != indexOfSelectedItem ? indexOfSelectedItem : nil
		onMenuDidCloseAction?(selectedIndex)
	}

	func menuWillOpen(_ menu: NSMenu) {
		currentlySelectedIndex = indexOfSelectedItem
		onMenuWillOpenAction?()
	}
}
