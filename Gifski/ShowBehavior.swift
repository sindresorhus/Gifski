enum ShowBehavior {
	case always(identifier: String)
	case onlyOnce(identifier: String)

	var identifier: String {
		switch self {
		case let .always(identifier), let .onlyOnce(identifier):
			return identifier
		}
	}

	var canShow: Bool {
		switch self {
		case .always:
			return true
		case .onlyOnce:
			return showCount < 1
		}
	}

	private var key: Defaults.Key<Int> {
		return Defaults.Key<Int>("showBehavior_" + identifier, default: 0)
	}

	private var showCount: Int {
		return defaults[key]
	}

	func didShow() {
		defaults[key] += 1
	}
}
