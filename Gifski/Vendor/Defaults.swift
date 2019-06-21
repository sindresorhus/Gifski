// Vendored from: https://github.com/sindresorhus/Defaults
import Foundation

public final class Defaults {
	public class Keys {
		public typealias Key = Defaults.Key
		public typealias OptionalKey = Defaults.OptionalKey

		fileprivate init() {}
	}

	public final class Key<T: Codable>: Keys {
		public let name: String
		public let defaultValue: T
		public let suite: UserDefaults

		public init(_ key: String, default defaultValue: T, suite: UserDefaults = .standard) {
			self.name = key
			self.defaultValue = defaultValue
			self.suite = suite

			super.init()

			// Sets the default value in the actual UserDefaults, so it can be used in other contexts, like binding.
			if UserDefaults.isNativelySupportedType(T.self) {
				suite.register(defaults: [key: defaultValue])
			} else if let value = suite._encode(defaultValue) {
				suite.register(defaults: [key: value])
			}
		}
	}

	public final class OptionalKey<T: Codable>: Keys {
		public let name: String
		public let suite: UserDefaults

		public init(_ key: String, suite: UserDefaults = .standard) {
			self.name = key
			self.suite = suite
		}
	}

	fileprivate init() {}

	public subscript<T: Codable>(key: Defaults.Key<T>) -> T {
		get {
			return key.suite[key]
		}
		set {
			key.suite[key] = newValue
		}
	}

	public subscript<T: Codable>(key: Defaults.OptionalKey<T>) -> T? {
		get {
			return key.suite[key]
		}
		set {
			key.suite[key] = newValue
		}
	}

	public func clear(suite: UserDefaults = .standard) {
		for key in suite.dictionaryRepresentation().keys {
			suite.removeObject(forKey: key)
		}
	}
}

// Has to be `defaults` lowercase until Swift supports static subscripts…
public let defaults = Defaults()

extension UserDefaults {
	private func _get<T: Codable>(_ key: String) -> T? {
		if UserDefaults.isNativelySupportedType(T.self) {
			return object(forKey: key) as? T
		}

		guard
			let text = string(forKey: key),
			let data = "[\(text)]".data(using: .utf8)
		else {
			return nil
		}

		do {
			return (try JSONDecoder().decode([T].self, from: data)).first
		} catch {
			print(error)
		}

		return nil
	}

	fileprivate func _encode<T: Codable>(_ value: T) -> String? {
		do {
			// Some codable values like URL and enum are encoded as a top-level
			// string which JSON can't handle, so we need to wrap it in an array
			// We need this: https://forums.swift.org/t/allowing-top-level-fragments-in-jsondecoder/11750
			let data = try JSONEncoder().encode([value])
			return String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
		} catch {
			print(error)
			return nil
		}
	}

	private func _set<T: Codable>(_ key: String, to value: T) {
		if UserDefaults.isNativelySupportedType(T.self) {
			set(value, forKey: key)
			return
		}

		set(_encode(value), forKey: key)
	}

	public subscript<T: Codable>(key: Defaults.Key<T>) -> T {
		get {
			return _get(key.name) ?? key.defaultValue
		}
		set {
			_set(key.name, to: newValue)
		}
	}

	public subscript<T: Codable>(key: Defaults.OptionalKey<T>) -> T? {
		get {
			return _get(key.name)
		}
		set {
			guard let value = newValue else {
				set(nil, forKey: key.name)
				return
			}

			_set(key.name, to: value)
		}
	}

	fileprivate static func isNativelySupportedType<T>(_ type: T.Type) -> Bool {
		switch type {
		case is Bool.Type,
			 is String.Type,
			 is Int.Type,
			 is Double.Type,
			 is Float.Type,
			 is Date.Type,
			 is Data.Type:
			return true
		default:
			return false
		}
	}
}

// TODO: Nest this inside `Defaults` if Swift ever supported nested protocols.
public protocol DefaultsObservation {
	func invalidate()
}

extension Defaults {
	private static func deserialize<T: Decodable>(_ value: Any?, to type: T.Type) -> T? {
		guard
			let value = value,
			!(value is NSNull)
		else {
			return nil
		}

		// This handles the case where the value was a plist value using `isNativelySupportedType`
		if let value = value as? T {
			return value
		}

		// Using the array trick as done below in `UserDefaults#_set()`
		return [T].init(jsonString: "\([value])")?.first
	}

	fileprivate final class BaseChange {
		fileprivate let kind: NSKeyValueChange
		fileprivate let indexes: IndexSet?
		fileprivate let isPrior: Bool
		fileprivate let newValue: Any?
		fileprivate let oldValue: Any?

		fileprivate init(change: [NSKeyValueChangeKey: Any]) {
			kind = NSKeyValueChange(rawValue: change[.kindKey] as! UInt)!
			indexes = change[.indexesKey] as? IndexSet
			isPrior = change[.notificationIsPriorKey] as? Bool ?? false
			oldValue = change[.oldKey]
			newValue = change[.newKey]
		}
	}

	public struct KeyChange<T: Codable> {
		public let kind: NSKeyValueChange
		public let indexes: IndexSet?
		public let isPrior: Bool
		public let newValue: T
		public let oldValue: T

		fileprivate init(change: BaseChange, defaultValue: T) {
			self.kind = change.kind
			self.indexes = change.indexes
			self.isPrior = change.isPrior
			self.oldValue = deserialize(change.oldValue, to: T.self) ?? defaultValue
			self.newValue = deserialize(change.newValue, to: T.self) ?? defaultValue
		}
	}

	public struct OptionalKeyChange<T: Codable> {
		public let kind: NSKeyValueChange
		public let indexes: IndexSet?
		public let isPrior: Bool
		public let newValue: T?
		public let oldValue: T?

		fileprivate init(change: BaseChange) {
			self.kind = change.kind
			self.indexes = change.indexes
			self.isPrior = change.isPrior
			self.oldValue = deserialize(change.oldValue, to: T.self)
			self.newValue = deserialize(change.newValue, to: T.self)
		}
	}

	private final class UserDefaultsKeyObservation: NSObject, DefaultsObservation {
		fileprivate typealias Callback = (BaseChange) -> Void

		private weak var object: UserDefaults?
		private let key: String
		private let callback: Callback

		fileprivate init(object: UserDefaults, key: String, callback: @escaping Callback) {
			self.object = object
			self.key = key
			self.callback = callback
		}

		deinit {
			invalidate()
		}

		fileprivate func start(options: NSKeyValueObservingOptions) {
			object?.addObserver(self, forKeyPath: key, options: options, context: nil)
		}

		public func invalidate() {
			object?.removeObserver(self, forKeyPath: key, context: nil)
			object = nil
		}

		// swiftlint:disable:next block_based_kvo
		override func observeValue(
			forKeyPath keyPath: String?,
			of object: Any?,
			change: [NSKeyValueChangeKey: Any]?, // swiftlint:disable:this discouraged_optional_collection
			context: UnsafeMutableRawPointer?
		) {
			guard
				let selfObject = self.object,
				selfObject == object as? NSObject,
				let change = change
			else {
				return
			}

			callback(BaseChange(change: change))
		}
	}

	/**
	Observe a defaults key

	```
	extension Defaults.Keys {
		static let isUnicornMode = Key<Bool>("isUnicornMode", default: false)
	}

	let observer = defaults.observe(.isUnicornMode) { change in
		print(change.newValue)
		//=> false
	}
	```
	*/
	public func observe<T: Codable>(
		_ key: Defaults.Key<T>,
		options: NSKeyValueObservingOptions = [.initial, .old, .new],
		handler: @escaping (KeyChange<T>) -> Void
	) -> DefaultsObservation {
		let observation = UserDefaultsKeyObservation(object: key.suite, key: key.name) { change in
			handler(
				KeyChange<T>(change: change, defaultValue: key.defaultValue)
			)
		}
		observation.start(options: options)
		return observation
	}

	/**
	Observe an optional defaults key

	```
	extension Defaults.Keys {
		static let isUnicornMode = OptionalKey<Bool>("isUnicornMode")
	}

	let observer = defaults.observe(.isUnicornMode) { change in
		print(change.newValue)
		//=> Optional(nil)
	}
	```
	*/
	public func observe<T: Codable>(
		_ key: Defaults.OptionalKey<T>,
		options: NSKeyValueObservingOptions = [.initial, .old, .new],
		handler: @escaping (OptionalKeyChange<T>) -> Void
	) -> DefaultsObservation {
		let observation = UserDefaultsKeyObservation(object: key.suite, key: key.name) { change in
			handler(
				OptionalKeyChange<T>(change: change)
			)
		}
		observation.start(options: options)
		return observation
	}
}

extension Decodable {
	init?(jsonData: Data) {
		guard let value = try? JSONDecoder().decode(Self.self, from: jsonData) else {
			return nil
		}

		self = value
	}

	init?(jsonString: String) {
		guard let data = jsonString.data(using: .utf8) else {
			return nil
		}

		self.init(jsonData: data)
	}
}
