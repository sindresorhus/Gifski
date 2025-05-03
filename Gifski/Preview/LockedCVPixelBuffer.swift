//
//  copyCVPixelBuffers.swift
//  Gifski
//
//  Created by Michael Mulet on 4/24/25.
//

import Foundation
import CoreVideo

/**
 A CVPixelBuffer that has had it's base address locked via [CVPixelBufferLockBaseAddress](CVPixelBufferLockBaseAddress)
 */
protocol LockedCVPixelBuffer {
	var buf: CVPixelBuffer {get}
}

final class ReadableCVPixelBuffer: LockedCVPixelBuffer {
	let buf: CVPixelBuffer
	init(buf: CVPixelBuffer){
		self.buf = buf
		CVPixelBufferLockBaseAddress(buf, [.readOnly])
	}
	deinit {
		CVPixelBufferUnlockBaseAddress(buf, [.readOnly])
	}
}

/**
 When using  ReadWriteableCVPixelBuffer  as a parameter, mark it as inout to express that the buffer contents will change
 */
final class ReadWriteableCVPixelBuffer: LockedCVPixelBuffer {
	let buf: CVPixelBuffer
	init(buf: inout CVPixelBuffer) {
		self.buf = buf
		CVPixelBufferLockBaseAddress(buf, [])
	}
	deinit{
		CVPixelBufferUnlockBaseAddress(buf, [])
	}
}

extension LockedCVPixelBuffer {
	/**
	 - Returns: True if copy was successful, false on error
	 */
	func copy(to destination: inout ReadWriteableCVPixelBuffer) -> Bool {
		// 0 in the cse of NonPlanar buffers
		let planeCount = CVPixelBufferGetPlaneCount(buf)
		guard planeCount == CVPixelBufferGetPlaneCount(destination.buf) else {
			return false
		}
		let planes = planeCount == 0 ? [nil] : Array(0..<planeCount).map { Optional($0) }
		for planeIndex in planes {
			guard let source = PixelBufferByteCopier(buffer: self, plane: planeIndex),
				  var destination = PixelBufferByteCopier(buffer: destination, plane: planeIndex)
			else {
				return false
			}
			guard source.copy(to: &destination) else {
				return false
			}
		}
		return true
	}
	func makeANewBufferThatThisCanCopyTo() -> CVPixelBuffer? {
		var out: CVPixelBuffer?
		guard CVPixelBufferCreate(kCFAllocatorDefault, CVPixelBufferGetWidth(buf), CVPixelBufferGetHeight(buf), CVPixelBufferGetPixelFormatType(buf), CVPixelBufferCopyCreationAttributes(buf), &out) == kCVReturnSuccess
		else {
			return nil
		}
		return out
	}
}

/**
 Helper class to make [LockedCVPixelBuffer.copy](LockedCVPixelBuffer.copy(to:)) more elegant. It handles copying for planar and non planer frames in the same way
 */
fileprivate struct PixelBufferByteCopier<B: LockedCVPixelBuffer> {
	private let baseAddress: UnsafeMutableRawPointer
	private let width: Int
	private let height: Int
	private let bytesPerRow: Int
	private let pixelFormatType: OSType

	private var rowPointer: UnsafeMutableRawPointer
	private var rowIndex = 0
	init?(buffer lockedBuffer: B, plane: Int? = nil) {
		let buffer = lockedBuffer.buf
		pixelFormatType = CVPixelBufferGetPixelFormatType(buffer)
		if let plane {
			guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else {
				return nil
			}
			self.baseAddress = baseAddress
			width = CVPixelBufferGetWidthOfPlane(buffer, plane)
			height = CVPixelBufferGetHeightOfPlane(buffer, plane)
			bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
			rowPointer = baseAddress
			return
		}
		guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
			return nil
		}
		self.baseAddress = baseAddress
		width = CVPixelBufferGetWidth(buffer)
		height = CVPixelBufferGetHeight(buffer)
		bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
		rowPointer = baseAddress
	}
	func copy(to originalDestination: inout PixelBufferByteCopier<ReadWriteableCVPixelBuffer>) -> Bool {
		var source = self
		var destination = originalDestination
		guard source.height == destination.height,
			  source.width == destination.width,
			  source.pixelFormatType == destination.pixelFormatType
		else {
			return false
		}

		guard source.bytesPerRow != destination.bytesPerRow else {
			memcpy(destination.baseAddress, source.baseAddress, source.height * source.bytesPerRow)
			return true
		}
		for _ in 0..<source.height {
			memcpy(destination.rowPointer, source.rowPointer, min(source.bytesPerRow, destination.bytesPerRow))
			destination.advanceRow()
			source.advanceRow()
		}
		return true
	}
	private mutating func advanceRow() {
		guard rowIndex < height - 1 else {
			return
		}
		rowPointer = rowPointer.advanced(by: bytesPerRow)
		rowIndex += 1
	}
}
