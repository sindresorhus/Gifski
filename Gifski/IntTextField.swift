import AppKit
import Carbon

final class IntTextField: NSTextField, NSTextFieldDelegate {

	override var canBecomeKeyView: Bool {
		return true
	}

	// Delta used for arrow navigation
	var delta = 1

	// Delta used for option + arrow navigation
	var alternativeDelta = 10

	var onBlur: ((Int) -> Void)?
	var onValidValueChange: ((Int) -> Void)?
	var minMax: ClosedRange<Int>?

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
		guard window?.firstResponder == currentEditor() else {
			return super.performKeyEquivalent(with: event)
		}

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
		handleChangedText()

		return true
	}

	func controlTextDidChange(_ object: Notification) {
		handleChangedText()
	}

	func controlTextDidEndEditing(_ object: Notification) {
		if !isValid(integerValue) {
			indicateValidationFailure()
		}
		onBlur?(integerValue)
	}

	func indicateValidationFailure() {
		shake(direction: .horizontal)
	}

	private func handleChangedText() {
		if isValid(integerValue) {
			onValidValueChange?(integerValue)
		} else {
			indicateValidationFailure()
		}
	}

	private func isValid(_ value: Int) -> Bool {
		guard let minMax = minMax else {
			return true
		}

		return minMax.contains(value)
	}
}
