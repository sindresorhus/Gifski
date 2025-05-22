//
//  copyCVPixelBuffers.swift
//  Gifski
//
//  Created by Michael Mulet on 4/24/25.
//

import Foundation
import CoreVideo

extension CVPixelBuffer {
	/**
	 - Returns: True if copy was successful, false on error
	 */
	func copy(to destination: CVPixelBuffer) throws {
		try withLockedPlanes(flags: [.readOnly]) { sourcePlanes in
			try destination.withLockedPlanes(flags: []) { destinationPlanes in
				guard sourcePlanes.count == destinationPlanes.count else {
					throw CopyError.planesMismatch
				}
				for (sourcePlane, destinationPlane) in zip(sourcePlanes, destinationPlanes) {
					try sourcePlane.copy(to: destinationPlane)
				}
			}
		}
	}

	enum CopyError: Error {
		case planesMismatch
		case heightMismatch
	}

	func withLockedBaseAddress<T>(
		flags: CVPixelBufferLockFlags = [],
		_ body: (CVPixelBuffer) throws -> T?
	) rethrows -> T? {
		guard CVPixelBufferLockBaseAddress(self, flags) == kCVReturnSuccess else {
			return nil
		}
		defer { CVPixelBufferUnlockBaseAddress(self, flags) }
		return try body(self)
	}

	func withLockedPlanes<T>(
		flags: CVPixelBufferLockFlags = [],
		_ body: ([LockedPlane]) throws -> T?
	) rethrows -> T? {
		try withLockedBaseAddress(flags: flags) { buffer in
			let planeCount = buffer.planeCount
			if planeCount == 0 {
				guard let base = buffer.baseAddress else {
					return nil
				}
				return try body([
					.init(
						base: base,
						bytesPerRow: buffer.bytesPerRow,
						height: buffer.height
					)
				])
			}
			let planes = (0..<planeCount).compactMap { planeIndex -> LockedPlane? in
				guard let base = buffer.baseAddressOfPlane(planeIndex) else {
					return nil
				}
				return .init(
					base: base,
					bytesPerRow: buffer.bytesPerRowOfPlane(planeIndex),
					height: buffer.heightOfPlane(planeIndex)
				)
			}
			guard planes.count == planeCount else {
				return nil
			}
			return try body(planes)
		}
	}

	func makeCompatibleBuffer() -> CVPixelBuffer? {
		var out: CVPixelBuffer?
		guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormatType, creationAttributes, &out) == kCVReturnSuccess
		else {
			return nil
		}
		return out
	}

	struct LockedPlane {
		let base: UnsafeMutableRawPointer
		let bytesPerRow: Int
		let height: Int

		func copy(to destination: Self) throws {
			guard height == destination.height
			else {
				throw CopyError.heightMismatch
			}

			guard bytesPerRow != destination.bytesPerRow else {
				memcpy(destination.base, base, height * bytesPerRow)
				return
			}
			var destinationBase = destination.base
			var sourceBase = base

			let minBytesPerRow = min(bytesPerRow, destination.bytesPerRow)
			for _ in 0..<height {
				memcpy(destinationBase, sourceBase, minBytesPerRow)
				sourceBase = sourceBase.advanced(by: bytesPerRow)
				destinationBase = destinationBase.advanced(by: destination.bytesPerRow)
			}
			return
		}
	}
}
