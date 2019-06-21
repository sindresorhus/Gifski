import AppKit

final class Tooltip: NSPopover {
	init(text: String, closeOnClick: Bool = true, contentInsets: NSEdgeInsets = .init(all: 10.0), maxWidth: Double? = nil) {
		super.init()
		setupContent(text: text, closeOnClick: closeOnClick, contentInsets: contentInsets, maxWidth: maxWidth)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupContent(text: "", closeOnClick: true, contentInsets: .zero, maxWidth: nil)
	}

	func show(from positioningView: NSView, preferredEdge: NSRectEdge) {
		show(relativeTo: positioningView.bounds, of: positioningView, preferredEdge: preferredEdge)
	}

	private func setupContent(text: String, closeOnClick: Bool, contentInsets: NSEdgeInsets, maxWidth: Double?) {
		contentViewController = ToolTipViewController(text: text, contentInsets: contentInsets, maxWidth: maxWidth) { [weak self] in
			if closeOnClick {
				self?.close()
			}
		}
		behavior = closeOnClick ? .transient : .applicationDefined
	}
}

fileprivate final class ToolTipViewController: NSViewController {
	fileprivate var text: String
	fileprivate var contentInsets: NSEdgeInsets
	fileprivate var maxWidth: Double?
	fileprivate var onClick: (() -> Void)?

	private lazy var clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(didClick))

	init(text: String, contentInsets: NSEdgeInsets, maxWidth: Double?, onClick: (() -> Void)?) {
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
			let newSize = textField.sizeThatFits(NSSize(width: CGFloat(maxWidth) - contentInsets.horizontal, height: .greatestFiniteMagnitude))
			textField.constrain(size: newSize)
		}

		wrapperView.addSubview(textField)
		textField.pinToSuperview(insets: contentInsets)

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
