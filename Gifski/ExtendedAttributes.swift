import AppKit

extension POSIXError {
	/// Create an error from the global C `errno`.
	static let fromErrno = Self(errno: errno)

	/**
	Create an error from the given C `errno`.

	```
	let length = getxattr(fileSystemPath, name, nil, 0, 0, 0)

	guard length >= 0 else {
		throw POSIXError(errno: errno)
	}
	```
	*/
	init(errno errorCode: Int32) {
		self.init(POSIXErrorCode(rawValue: errorCode) ?? .EPERM)
	}
}


final class ExtendedAttributes {
	let url: URL

	init(url: URL) {
		self.url = url
	}

	private func checkIfFileURL() throws {
		guard url.isFileURL else {
			throw CocoaError(.fileNoSuchFile)
		}
	}

	func has(_ name: String) -> Bool {
		guard url.isFileURL else {
			return false
		}

		return url.withUnsafeFileSystemRepresentation { fileSystemPath in
			getxattr(fileSystemPath, name, nil, 0, 0, 0) > 0
		}
	}

	func get(_ name: String) throws -> Data {
		try checkIfFileURL()

		return try url.withUnsafeFileSystemRepresentation { fileSystemPath in
			let length = getxattr(fileSystemPath, name, nil, 0, 0, 0)

			guard length >= 0 else {
				throw POSIXError.fromErrno
			}

			var data = Data(count: length)

			let result = data.withUnsafeMutableBytes {
				getxattr(fileSystemPath, name, $0.baseAddress, length, 0, 0)
			}

			guard result >= 0 else {
				throw POSIXError.fromErrno
			}

			return data
		}
	}

	/**
	- Note: Ensure you specify a type.

	```
	let isProtected: Bool = try? attributes.get("com.apple.rootless") ?? false
	```
	*/
	func get<T>(_ name: String) throws -> T {
		try checkIfFileURL()

		let data = try get(name)

		let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

		guard let result = value as? T else {
			throw CocoaError(.propertyListReadCorrupt)
		}

		return result
	}

	func set(_ name: String, data: Data) throws {
		try checkIfFileURL()

		try url.withUnsafeFileSystemRepresentation { fileSystemPath in
			let result = data.withUnsafeBytes {
				setxattr(fileSystemPath, name, $0.baseAddress, data.count, 0, 0)
			}

			guard result >= 0 else {
				throw POSIXError.fromErrno
			}
		}
	}

	func set<T>(_ name: String, value: T) throws {
		try checkIfFileURL()

		guard PropertyListSerialization.propertyList(value, isValidFor: .binary) else {
			throw CocoaError(.propertyListWriteInvalid)
		}

		let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
		try set(name, data: data)
	}

	func remove(_ name: String) throws {
		try checkIfFileURL()

		try url.withUnsafeFileSystemRepresentation { fileSystemPath in
			guard removexattr(fileSystemPath, name, 0) >= 0 else {
				throw POSIXError.fromErrno
			}
		}
	}

	/// Get all the extended attribute names.
	func all() throws -> [String] {
		try checkIfFileURL()

		let list: [String] = try url.withUnsafeFileSystemRepresentation { fileSystemPath in
			let length = listxattr(fileSystemPath, nil, 0, 0)

			guard length >= 0 else {
				throw POSIXError.fromErrno
			}

			var data = Data(count: length)

			let result = data.withUnsafeMutableBytes {
				listxattr(fileSystemPath, UnsafeMutablePointer<Int8>(OpaquePointer($0.baseAddress)), length, 0)
			}

			guard result >= 0 else {
				throw POSIXError.fromErrno
			}

			let list = data.split(separator: 0).compactMap {
				String(data: Data($0), encoding: .utf8)
			}

			return list
		}

		return list
	}

	func debug() {
		print("Extended attributes:\n\(try! all().joined(separator: "\n"))")
	}
}


extension URL {
	var attributes: ExtendedAttributes { .init(url: self) }
}
