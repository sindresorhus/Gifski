import AppKit
import Carbon

final class IntTextField: NSTextField, NSTextFieldDelegate {
	// Delta used for arrow navigation
	var delta = 1

	// Delta used for option + arrow navigation
	var biggerDelta = 10

	var onBlur: ((Int) -> Void)?
	var onTextDidChange: ((Int) -> Void)?

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setup()
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		setup()
	}

	private func setup() {
		delegate = self
	}

	override func performKeyEquivalent(with event: NSEvent) -> Bool {
		let key = event.specialKey
		let isHoldingOption = event.modifierFlags.contains(.option)

		let delta: Int
		switch (key, isHoldingOption) {
		case (.upArrow?, true):
			delta = self.biggerDelta
		case (.upArrow?, false):
			delta = self.delta
		case (.downArrow?, true):
			delta = -1 * self.biggerDelta
		case (.downArrow?, false):
			delta = -1 * self.delta
		default:
			return super.performKeyEquivalent(with: event)
		}

		let currentValue = Int(stringValue) ?? 0
		let newValue = currentValue + delta
		stringValue = "\(newValue)"
		onTextDidChange?(newValue)

		return true
	}

	func controlTextDidChange(_ obj: Notification) {
		onTextDidChange?(integerValue)
	}

	func controlTextDidEndEditing(_ obj: Notification) {
		onBlur?(integerValue)
	}
}
