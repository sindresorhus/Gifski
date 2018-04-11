// Vendored from: https://github.com/sindresorhus/Defaults
import Cocoa

public final class Defaults {
	public class Keys {}

	public final class Key<T: Codable>: Keys {
		fileprivate let name: String
		fileprivate let defaultValue: T

		init(_ key: String, default defaultValue: T) {
			self.name = key
			self.defaultValue = defaultValue
		}
	}

	public final class OptionalKey<T: Codable>: Keys {
		fileprivate let name: String

		init(_ key: String) {
			self.name = key
		}
	}

	public subscript<T: Codable>(key: Defaults.Key<T>) -> T {
		get {
			return UserDefaults.standard[key]
		}
		set {
			UserDefaults.standard[key] = newValue
		}
	}

	public subscript<T: Codable>(key: Defaults.OptionalKey<T>) -> T? {
		get {
			return UserDefaults.standard[key]
		}
		set {
			UserDefaults.standard[key] = newValue
		}
	}

	public func clear() {
		for key in UserDefaults.standard.dictionaryRepresentation().keys {
			UserDefaults.standard.removeObject(forKey: key)
		}
	}
}

// Has to be `defaults` lowercase until Swift supports static subscripts…
public let defaults = Defaults()

public extension UserDefaults {
	private func _get<T: Codable>(_ key: String) -> T? {
		if isNativelySupportedType(T.self) {
			return object(forKey: key) as? T
		}

		guard let text = string(forKey: key),
			let data = "[\(text)]".data(using: .utf8) else {
				return nil
		}

		do {
			return (try JSONDecoder().decode([T].self, from: data)).first
		} catch {
			print(error)
		}

		return nil
	}

	private func _set<T: Codable>(_ key: String, to value: T) {
		if isNativelySupportedType(T.self) {
			set(value, forKey: key)
			return
		}

		do {
			// Some codable values like URL and enum are encoded as a top-level
			// string which JSON can't handle, so we need to wrap it in an array
			// We need this: https://forums.swift.org/t/allowing-top-level-fragments-in-jsondecoder/11750
			let data = try JSONEncoder().encode([value])
			let string = String(data: data, encoding: .utf8)?.dropFirst().dropLast()
			set(string, forKey: key)
		} catch {
			print(error)
		}
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
			if let value = newValue {
				_set(key.name, to: value)
			}
		}
	}

	private func isNativelySupportedType<T>(_ type: T.Type) -> Bool {
		switch type {
		case is Bool.Type,
			 is String.Type,
			 is Int.Type,
			 is Double.Type,
			 is Float.Type,
			 is Date.Type:
			return true
		default:
			return false
		}
	}
}
