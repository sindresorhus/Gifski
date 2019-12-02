import AppKit
import Defaults

final class Tooltip: NSPopover {
	private let identifier: String
	private let showOnlyOnce: Bool

	private var showKey: Defaults.Key<Int> {
		Defaults.Key<Int>("__Tooltip__\(identifier)", default: 0)
	}

	init(
		identifier: String,
		text: String,
		showOnlyOnce: Bool = false,
		closeOnClick: Bool = true,
		contentInsets: NSEdgeInsets = .init(all: 15),
		maxWidth: Double? = nil
	) {
		self.identifier = identifier
		self.showOnlyOnce = showOnlyOnce
		super.init()

		setupContent(
			text: text,
			closeOnClick: closeOnClick,
			contentInsets: contentInsets,
			maxWidth: maxWidth
		)
	}

	required init?(coder: NSCoder) {
		self.identifier = UUID().uuidString
		self.showOnlyOnce = false
		super.init(coder: coder)

		setupContent(
			text: "",
			closeOnClick: true,
			contentInsets: .zero,
			maxWidth: nil
		)
	}

	func show(from positioningView: NSView, preferredEdge: NSRectEdge) {
		show(
			relativeTo: positioningView.bounds,
			of: positioningView,
			preferredEdge: preferredEdge
		)
	}

	override func show(
		relativeTo positioningRect: CGRect,
		of positioningView: NSView,
		preferredEdge: NSRectEdge
	) {
		guard positioningView.window != nil else {
			assertionFailure("Tooltip must be shown from a view with a window")
			return
		}

		if !showOnlyOnce || (showOnlyOnce && Defaults[showKey] < 1) {
			Defaults[showKey] += 1

			super.show(
				relativeTo: positioningRect,
				of: positioningView,
				preferredEdge: preferredEdge
			)
		}
	}

	private func setupContent(
		text: String,
		closeOnClick: Bool,
		contentInsets: NSEdgeInsets,
		maxWidth: Double?
	) {
		contentViewController = ToolTipViewController(text: text, contentInsets: contentInsets, maxWidth: maxWidth) { [weak self] in
			if closeOnClick {
				self?.close()
			}
		}

		behavior = closeOnClick ? .semitransient : .applicationDefined
	}
}

fileprivate final class ToolTipViewController: NSViewController {
	fileprivate let text: String
	fileprivate let contentInsets: NSEdgeInsets
	fileprivate var maxWidth: Double?
	fileprivate var onClick: (() -> Void)?

	private lazy var clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(didClick))

	init(
		text: String,
		contentInsets: NSEdgeInsets,
		maxWidth: Double?,
		onClick: (() -> Void)?
	) {
		self.text = text
		self.contentInsets = contentInsets
		self.maxWidth = maxWidth
		self.onClick = onClick
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		self.text = ""
		self.contentInsets = .zero
		super.init(coder: coder)
	}

	override func loadView() {
		let wrapperView = NSView()
		let textField = NSTextField(wrappingLabelWithString: text)
		textField.isSelectable = false

		if let maxWidth = maxWidth {
			let newSize = textField.sizeThatFits(
				CGSize(
					width: CGFloat(maxWidth - contentInsets.horizontal),
					height: .greatestFiniteMagnitude
				)
			)
			textField.constrain(to: newSize)
		}

		wrapperView.addSubview(textField)
		textField.constrainEdgesToSuperview(with: contentInsets)

		view = wrapperView
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		view.addGestureRecognizer(clickRecognizer)
	}

	@objc
	private func didClick() {
		onClick?()
	}
}
