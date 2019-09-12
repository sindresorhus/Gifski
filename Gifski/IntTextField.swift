import AppKit

final class IntTextField: NSTextField, NSTextFieldDelegate {
	override var canBecomeKeyView: Bool { true }

	/// Delta used for arrow navigation.
	var delta = 1

	/// Delta used for option + arrow navigation.
	var alternativeDelta = 10

	var onValueChange: ((Int) -> Void)?
	var onBlur: ((Int) -> Void)?
	var minMax: ClosedRange<Int>?
	var isEmpty: Bool { stringValue.trimmingCharacters(in: .whitespaces).isEmpty }

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setup()
	}

	override init(frame frameRect: CGRect) {
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
		handleValueChange()

		return true
	}

	func controlTextDidChange(_ object: Notification) {
		let isInvalidButInBounds = !isValid(integerValue) && integerValue > 0 && integerValue <= (minMax?.upperBound ?? Int.max)

		// For entered text we want to give a little bit more room to breathe
		if isEmpty || isInvalidButInBounds {
			return
		}

		handleValueChange()
	}

	private func handleValueChange() {
		if !isValid(integerValue) {
			indicateValidationFailure()
		}

		onValueChange?(integerValue)
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

	private func isValid(_ value: Int) -> Bool {
		guard let minMax = minMax else {
			return true
		}

		return minMax.contains(value)
	}
}
