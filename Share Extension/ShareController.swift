import SwiftUI

final class ShareController: ExtensionController {
	override func run(_ context: NSExtensionContext) async throws -> [NSExtensionItem] {
		guard
			let url = try await (context.attachments.first { $0.hasItemConforming(to: .url) })?.loadTransferable(type: URL.self)
		else {
			context.cancel()
			return []
		}

		let filename = url.lastPathComponent

		guard
			let appGroupShareVideoURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.appGroupIdentifier)?.appendingPathComponent(filename, isDirectory: false)
		else {
			context.cancel()
			return []
		}

		try? FileManager.default.removeItem(at: appGroupShareVideoURL)
		try FileManager.default.copyItem(at: url, to: appGroupShareVideoURL)

		let gifskiURL = createMainAppUrl(
			queryItems: [
				URLQueryItem(name: "path", value: filename)
			]
		)

		NSWorkspace.shared.open(gifskiURL)

		return []
	}

	private func createMainAppUrl(queryItems: [URLQueryItem]) -> URL {
		var components = URLComponents()
		components.scheme = "gifski"
		components.host = "shareExtension"
		components.queryItems = queryItems
		return components.url!
	}
}
