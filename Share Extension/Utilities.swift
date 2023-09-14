import Cocoa
import UniformTypeIdentifiers


extension Sequence where Element: Sequence {
	func flatten() -> [Element.Element] {
		// TODO: Make this `flatMap(\.self)` when https://github.com/apple/swift/issues/55343 is fixed.
		flatMap { $0 }
	}
}


extension NSExtensionContext {
	var inputItemsTyped: [NSExtensionItem] { inputItems as! [NSExtensionItem] }

	var attachments: [NSItemProvider] {
		inputItemsTyped.compactMap(\.attachments).flatten()
	}
}


// Strongly-typed versions of some of the methods.
extension NSItemProvider {
	func hasItemConforming(to contentType: UTType) -> Bool {
		hasItemConformingToTypeIdentifier(contentType.identifier)
	}
}
