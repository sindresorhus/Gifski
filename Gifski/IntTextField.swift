import AppKit
import Carbon

final class IntTextField: NSTextField, NSTextFieldDelegate {
	// Delta used for arrow navigation
	var delta = 1

	// Delta used for option + arrow navigation
	var alternativeDelta = 10

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
		let initialDelta = isHoldingOption ? alternativeDelta : delta

		let delta: Int
		switch key {
		case .upArrow?:
			delta = initialDelta
		case .downArrow?:
			delta = initialDelta * -1
		default:
			return super.performKeyEquivalent(with: event)
		}

		let currentValue = Int(stringValue) ?? 0
		let newValue = currentValue + delta
		stringValue = "\(newValue)"
		onTextDidChange?(newValue)

		return true
	}

	func controlTextDidChange(_ object: Notification) {
		onTextDidChange?(integerValue)
	}

	func controlTextDidEndEditing(_ object: Notification) {
		onBlur?(integerValue)
	}

	func indicateValidationFailure() {
		shake(direction: .horizontal)
	}
}
