import AppKit

final class MenuPopUpButton: NSPopUpButton, NSMenuDelegate {
	override var acceptsFirstResponder: Bool { true }
	override var canBecomeKeyView: Bool { true }

	/// `selectedIndex` is nil when the user didn't select any index this time (probably quit).
	var onMenuDidClose: ((_ selectedIndex: Int?) -> Void)?
	var onMenuWillOpen: (() -> Void)?

	/// If true, it will regain focus once the menu has been touched.
	var shouldFocus = true

	private var currentlySelectedIndex: Int?

	override func awakeFromNib() {
		super.awakeFromNib()
		menu?.delegate = self
	}

	func menuDidClose(_ menu: NSMenu) {
		let selectedIndex = currentlySelectedIndex != indexOfSelectedItem ? indexOfSelectedItem : nil
		onMenuDidClose?(selectedIndex)

		if shouldFocus {
			focus()
		}
	}

	func menuWillOpen(_ menu: NSMenu) {
		currentlySelectedIndex = indexOfSelectedItem
		onMenuWillOpen?()
	}
}
