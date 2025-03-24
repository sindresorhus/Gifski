//
//  ActionRequestHandler.swift
//  Quick Convert to GIF with Gifski
//
//  Created by Michael Mulet on 3/23/25.

import Foundation
import UniformTypeIdentifiers
import AppKit

final class ActionRequestHandler: NSObject, @preconcurrency NSExtensionRequestHandling {
	@MainActor
	func beginRequest(with context: NSExtensionContext) {
		guard let item = context.inputItems[0] as? NSExtensionItem else {
			context.cancelRequest(withError: QuickGifskiError.failedToFindExtensionItem)
			return
		}

		/// This task is terminal (no code afterwards) and on @MainActor
		/// So we can guarantee that sending item will not cause
		/// a data-race
		Task {
			@MainActor in
			let result = await convertToGif(item: item)
			switch result {
			case .success:
				context.completeRequest(returningItems: [item], completionHandler: nil)
			case .failure(let error):
				context.cancelRequest(withError: error)
			}
		}
	}
}

func convertToGif(item: NSExtensionItem) async -> Result<Void, Error> {
	do {
		guard let url = try await getURLFromItem(item) else {
			return .failure(QuickGifskiError.failedToRetrieveURL)
		}
		guard url.startAccessingSecurityScopedResource() else {
			print("Failed to access security-scoped resource")
			return .failure(QuickGifskiError.failedToAccessSecurityScopedResource)
		}
		defer { url.stopAccessingSecurityScopedResource() }

		let (asset, metadata) = try await VideoValidator.validate(url)

		let modifiedAsset = try await asset.firstVideoTrack?.extractToNewAssetAndChangeSpeed(to: Defaults[.quickOutputSpeed]) ?? asset

		let scale = Defaults[.quickResize]

		let conversion = GIFGenerator.Conversion(
			asset: modifiedAsset,
			sourceURL: url,
			timeRange: 0...metadata.duration.toTimeInterval,
			quality: Defaults[.quickOutputQuality],
			dimensions: (
				max((scale * metadata.dimensions.width).toIntAndClampingIfNeeded, 1),
				max((scale * metadata.dimensions.height).toIntAndClampingIfNeeded, 1)
			),
			/// Cap the frame rate at the assetFrameRate
			frameRate: min(Defaults[.quickOutputFPS], metadata.frameRate.toIntAndClampingIfNeeded),
			loop: getLoop(),
			bounce: Defaults[.quickBounceGIF]
		)
		let data = try await GIFGenerator.run(conversion) { _ in
			/// no-op
		}
		guard let outputURL = try generateUnusedOutputFileURL(originalURL: url) else {
			return .failure(QuickGifskiError.failedToGenerateOutputURL)
		}
		try data.write(to: outputURL)
		NSWorkspace.shared.activateFileViewerSelecting([outputURL])

		return .success(())
	} catch {
		print("Unexpected error: \(error)")
		return .failure(QuickGifskiError.conversionFailed(error.localizedDescription))
	}
}



func getURLFromItem(_ inputItem: NSExtensionItem) async throws -> URL? {
	guard let inputAttachments = inputItem.attachments,
		  let firstAttachment = inputAttachments.first else {
		return nil
	}
	let supportedIdentifiers = [
		"public.mpeg-4",
		"com.apple.m4v-video",
		"com.apple.quicktime-movie"
	]

	let extensionType = supportedIdentifiers.first {
		firstAttachment.hasItemConformingToTypeIdentifier($0)
	}

	guard let extensionType else {
		return nil
	}

	let data = try await firstAttachment.loadItem(forTypeIdentifier: extensionType)
	guard let url = data as? NSURL else {
		NSLog("\(type(of: data))")
		return nil
	}
	return url as URL
}


func generateUnusedOutputFileURL(originalURL url: URL) throws -> URL?{
	let downloadsURL = try FileManager.default.url(
		for: .downloadsDirectory,
		in: .userDomainMask,
		appropriateFor: nil,
		create: false
	)

	for num in 0..<10_000 {
		let numberExtension = num == 0 ? "" : ".\(num)"
		let fileName = url.deletingPathExtension().lastPathComponent + ".gifski\(numberExtension).gif"
		let outURL = downloadsURL.appendingPathComponent(fileName)
		guard !outURL.exists else {
			continue
		}
		return outURL
	}

	return nil
}

func getLoop() -> Gifski.Loop {
	guard Defaults[.quickLoopGIF] else {
		return Defaults[.quickLoopCount] == 0 ? .never : .count(Defaults[.quickLoopCount])
	}
	return .forever
}

/**
 We can add unchecked Sendable to NSExtensionItem
 only because we can manually guarantee that there will be
 no data race in this code.
 */
extension NSExtensionItem: @unchecked @retroactive Sendable {}


enum QuickGifskiError: LocalizedError {
	case failedToFindExtensionItem
	case failedToRetrieveURL
	case failedToAccessSecurityScopedResource
	case failedToGenerateOutputURL
	case conversionFailed(String)

	var errorDescription: String? {
		switch self {
		case .failedToFindExtensionItem:
			return "Failed to find extension item."
		case .failedToRetrieveURL:
			return "Failed to retrieve URL from item."
		case .failedToAccessSecurityScopedResource:
			return "Failed to access security-scoped resource."
		case .failedToGenerateOutputURL:
			return "Failed to generate unused output file URL."
		case .conversionFailed(let message):
			return "Conversion failed: \(message)"
		}
	}
}
