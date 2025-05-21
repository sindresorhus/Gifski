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
	func copy(to destination: CVPixelBuffer) -> Bool {
		withLocked(flags: [.readOnly]) { sourcePlanes in
			destination.withLocked(flags: []) { destinationPlanes in
				guard sourcePlanes.count == destinationPlanes.count else {
					return false
				}
				for (sourcePlane, destinationPlane) in zip(sourcePlanes, destinationPlanes) {
					guard sourcePlane.copy(to: destinationPlane) else {
						return false
					}
				}
				return true
			}
		} ?? false
	}

	func withLocked<T>(flags: CVPixelBufferLockFlags = [], _ body: ([LockedPixelBufferPlane]) throws -> T?) rethrows -> T? {
		guard CVPixelBufferLockBaseAddress(self, flags) == kCVReturnSuccess else {
			return nil
		}
		defer { CVPixelBufferUnlockBaseAddress(self, flags) }
		let planeCount = CVPixelBufferGetPlaneCount(self)
		if planeCount == 0 {
			guard let base = CVPixelBufferGetBaseAddress(self) else {
				return nil
			}
			return try body([
				.init(
					base: base,
					bytesPerRow: CVPixelBufferGetBytesPerRow(self),
					height: CVPixelBufferGetHeight(self)
				)
			])
		}
		let planes = (0..<planeCount).compactMap { planeIndex -> LockedPixelBufferPlane? in
			guard let base = CVPixelBufferGetBaseAddressOfPlane(self, planeIndex) else {
				return nil
			}
			return
				.init(
					base: base,
					bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(self, planeIndex),
					height: CVPixelBufferGetHeightOfPlane(self, planeIndex)
				)
		}
		guard planes.count == planeCount else {
			return nil
		}
		return try body(planes)
	}

	func makeANewBufferThatThisCanCopyTo() -> CVPixelBuffer? {
		var out: CVPixelBuffer?
		guard CVPixelBufferCreate(kCFAllocatorDefault, CVPixelBufferGetWidth(self), CVPixelBufferGetHeight(self), CVPixelBufferGetPixelFormatType(self), CVPixelBufferCopyCreationAttributes(self), &out) == kCVReturnSuccess
		else {
			return nil
		}
		return out
	}
}

struct LockedPixelBufferPlane {
	let base: UnsafeMutableRawPointer
	let bytesPerRow: Int
	let height: Int

	func copy(to destination: Self) -> Bool {
		guard height == destination.height
		else {
			return false
		}

		guard bytesPerRow != destination.bytesPerRow else {
			memcpy(destination.base, base, height * bytesPerRow)
			return true
		}
		var destinationBase = destination.base
		var sourceBase = base

		let minBytesPerRow = min(bytesPerRow, destination.bytesPerRow)
		for _ in 0..<height {
			memcpy(destinationBase, sourceBase, minBytesPerRow)
			sourceBase = sourceBase.advanced(by: bytesPerRow)
			destinationBase = destinationBase.advanced(by: destination.bytesPerRow)
		}
		return true
	}
}
