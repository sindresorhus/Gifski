import AppKit

final class MenuPopUpButton: NSPopUpButton, NSMenuDelegate {

	/// `selectedIndex` is nil when the user didn't select any index this time (probably quit)
	var onMenuDidCloseAction: ((_ selectedIndex: Int?) -> Void)?
	var onMenuWillOpenAction: (() -> Void)?

	private var currentlySelectedIndex: Int?

	override func awakeFromNib() {
		super.awakeFromNib()
		menu?.delegate = self
	}

	func menuDidClose(_ menu: NSMenu) {
		let selectedIndex: Int? = currentlySelectedIndex != indexOfSelectedItem ? indexOfSelectedItem : nil
		onMenuDidCloseAction?(selectedIndex)
	}

	func menuWillOpen(_ menu: NSMenu) {
		currentlySelectedIndex = indexOfSelectedItem
		onMenuWillOpenAction?()
	}
}
