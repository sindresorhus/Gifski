import SwiftUI

// TODO: This does not correctly prevent larger numbers than `minMax`.

struct IntTextField: NSViewRepresentable {
	typealias NSViewType = IntTextFieldCocoa

	@Binding var value: Int
	var minMax: ClosedRange<Int>?
	var delta = 1
	var alternativeDelta = 10
	var alignment: NSTextAlignment?
	var font: NSFont?
	var onValueChange: ((Int) -> Void)?
	var onBlur: ((Int) -> Void)?
	var onInvalid: ((Int) -> Void)?

	func makeNSView(context: Context) -> IntTextFieldCocoa {
		let nsView = IntTextFieldCocoa()

		nsView.onValueChange = {
			value = $0
			onValueChange?($0)
		}

		nsView.onBlur = {
			value = $0
			onBlur?($0)
		}

		nsView.onInvalid = {
			onInvalid?($0)
		}

		return nsView
	}

	func updateNSView(_ nsView: IntTextFieldCocoa, context: Context) {
		nsView.stringValue = "\(value)" // We intentionally do not use `nsView.intValue` as it formats the number.
		nsView.minMax = minMax
		nsView.delta = delta
		nsView.alternativeDelta = alternativeDelta

		if let alignment {
			nsView.alignment = alignment
		}

		if let font {
			nsView.font = font
		}
	}
}

final class IntTextFieldCocoa: NSTextField, NSTextFieldDelegate, NSControlTextEditingDelegate {
	override var canBecomeKeyView: Bool { true }

	/**
	Delta used for arrow navigation.
	*/
	var delta = 1

	/**
	Delta used for option + arrow navigation.
	*/
	var alternativeDelta = 10

	var onValueChange: ((Int) -> Void)?
	var onBlur: ((Int) -> Void)?
	var onInvalid: ((Int) -> Void)?
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
		let tentativeNewValue = currentValue + delta

		func setValue() {
			stringValue = "\(tentativeNewValue)"
			handleValueChange()
		}

		if let minMax {
			if minMax.contains(tentativeNewValue) {
				setValue()
			} else {
				indicateValidationFailure(invalidValue: tentativeNewValue)
			}
		} else {
			setValue()
		}

		return true
	}

	func controlTextDidChange(_ object: Notification) {
		stringValue = stringValue
			.replacing(/\D+/, with: "") // Make sure only digits can be entered.
			.replacing(/^0/, with: "") // Don't allow leading zero.

		if let minMax {
			// Ensure the user cannot input more digits than the max.
			stringValue = String(stringValue.prefix("\(minMax.upperBound)".count))
		}

		let isInvalidButInBounds = !isValid(integerValue) && integerValue > 0 && integerValue <= (minMax?.upperBound ?? Int.max)

		// For entered text we want to give a little bit more room to breathe
		if isEmpty || isInvalidButInBounds {
			return
		}

		handleValueChange()
	}

	private func handleValueChange() {
		if !isValid(integerValue) {
			indicateValidationFailure(invalidValue: integerValue)
		}

		onValueChange?(integerValue)
	}

	func controlTextDidEndEditing(_ object: Notification) {
		if !isValid(integerValue) {
			indicateValidationFailure(invalidValue: integerValue)
		}

		onBlur?(integerValue)
	}

	func indicateValidationFailure(invalidValue: Int) {
		shake(direction: .horizontal)
		onInvalid?(invalidValue)
	}

	private func isValid(_ value: Int) -> Bool {
		guard let minMax else {
			return true
		}

		return minMax.contains(value)
	}
}
