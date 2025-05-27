import SwiftUI
import UniformTypeIdentifiers


extension Sequence where Element: Sequence {
	func flatten() -> [Element.Element] {
		flatMap(\.self)
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


extension NSError {
	static let userCancelled = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
}


extension NSExtensionContext {
	func cancel() {
		cancelRequest(withError: NSError.userCancelled)
	}
}


extension NSItemProvider {
	func loadTransferable<T: Transferable & Sendable>(type transferableType: T.Type) async throws -> T {
		try await withCheckedThrowingContinuation { continuation in
			_ = loadTransferable(type: transferableType) {
				continuation.resume(with: $0)
			}
		}
	}
}


class ExtensionController: NSViewController { // swiftlint:disable:this final_class
	init() {
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError() // swiftlint:disable:this fatal_error_message
	}

	override func loadView() {
		Task { @MainActor in // Not sure if this is needed, but added just in case.
			do {
				extensionContext!.completeRequest(
					returningItems: try await run(extensionContext!),
					completionHandler: nil
				)
			} catch {
				extensionContext!.cancelRequest(withError: error)
			}
		}
	}

	func run(_ context: NSExtensionContext) async throws -> [NSExtensionItem] { [] }
}


// TODO: Check if any of these can be removed when targeting macOS 15.
extension NSItemProvider: @retroactive @unchecked Sendable {}
