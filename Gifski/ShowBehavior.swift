struct ShowBehavior {
	enum Option {
		case always
		case once
	}

	static func always(identifier: String) -> ShowBehavior {
		return .init(identifier: identifier, option: .always)
	}

	static func once(identifier: String) -> ShowBehavior {
		return .init(identifier: identifier, option: .once)
	}

	let identifier: String
	let option: Option

	private var key: Defaults.Key<Int> {
		return Defaults.Key<Int>("__showBehavior_" + identifier, default: 0)
	}

	private var showCount: Int {
		return defaults[key]
	}

	var canShow: Bool {
		switch option {
		case .always:
			return true
		case .once:
			return showCount < 1
		}
	}

	func didShow() {
		defaults[key] += 1
	}
}
