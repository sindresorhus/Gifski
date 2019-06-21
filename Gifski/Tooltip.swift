import AppKit

final class Tooltip: NSPopover {
	init(text: String, closeOnClick: Bool = true, contentInsets: NSEdgeInsets = .zero, maxWidth: CGFloat? = nil) {
		super.init()
		setupContent(text: text, closeOnClick: closeOnClick, contentInsets: contentInsets, maxWidth: maxWidth)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
		setupContent(text: "", closeOnClick: true, contentInsets: .zero, maxWidth: nil)
	}

	private func setupContent(text: String, closeOnClick: Bool, contentInsets: NSEdgeInsets, maxWidth: CGFloat?) {
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
	fileprivate var maxWidth: CGFloat?
	fileprivate var onClick: (() -> Void)?

	private var clickRecognizer: NSClickGestureRecognizer?

	init(text: String, contentInsets: NSEdgeInsets, maxWidth: CGFloat?, onClick: (() -> Void)?) {
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

		if let maxWidth = maxWidth {
			textField.frame.size = textField.sizeThatFits(NSSize(width: maxWidth - contentInsets.horizontal, height: .greatestFiniteMagnitude))
		}
		textField.frame.origin = CGPoint(x: contentInsets.left, y: contentInsets.top)

		let contentSize = textField.frame.size
		let size = CGSize(width: contentSize.width + contentInsets.horizontal, height: contentSize.height + contentInsets.vertical)
		wrapperView.frame = CGRect(origin: .zero, size: size)
		wrapperView.addSubview(textField)

		view = wrapperView
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(didClick))
		view.addGestureRecognizer(clickRecognizer)
		self.clickRecognizer = clickRecognizer
	}

	@objc
	private func didClick() {
		onClick?()
	}
}

extension NSEdgeInsets {
	static var zero: NSEdgeInsets {
		return NSEdgeInsetsZero
	}

	init(value: CGFloat) {
		self.init(top: value, left: value, bottom: value, right: value)
	}

	var vertical: CGFloat {
		return top + bottom
	}

	var horizontal: CGFloat {
		return left + right
	}
}
