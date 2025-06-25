import Foundation
import Metal
import MetalKit

/**
Textures that can only be accessed on the `PreviewRenderer` actor.
*/
struct SendableTexture: @unchecked Sendable {
	private let texture: MTLTexture

	/*
	Kept fileprivate, because in this file we can ensure that the `SendableTexture` is isolated to the `PreviewRenderer`.
	*/
	fileprivate init(texture: MTLTexture) {
		self.texture = texture
	}

	func getTexture(isolated: isolated PreviewRenderer) -> MTLTexture {
		texture
	}
}

extension PreviewRenderer {
	func convertToTexture(data: Data) async throws -> SendableTexture {
		try await newSendableTexture(source: .data(data), options: textureOptions)
	}

	func convertToTexture(cgImage: CGImage) async throws -> SendableTexture {
		try await newSendableTexture(source: .image(cgImage), options: textureOptions)
	}

	private var textureOptions: [MTKTextureLoader.Option: Any] {
		[
			.SRGB: false,
			.origin: MTKTextureLoader.Origin.flippedVertically
		]
	}

	func newSendableTexture(
		source: SendableTextureSource,
		options: [MTKTextureLoader.Option: Any]? = nil // swiftlint:disable:this discouraged_optional_collection
	) async throws -> SendableTexture {
		try await withCheckedThrowingContinuation { continuation in
			// Use the callback version of `newTexture` so that Swift 6 will compile.
			let callback: MTKTextureLoader.Callback = { texture, error in
				guard let texture else {
					continuation.resume(throwing: error ?? PreviewRenderer.Error.failedToMakeSendableTexture)
					return
				}

				continuation.resume(returning: SendableTexture(texture: texture))
			}

			switch source {
			case .data(let data):
				textureLoader.newTexture(
					data: data,
					options: options,
					completionHandler: callback
				)
			case .image(let image):
				textureLoader.newTexture(
					cgImage: image,
					options: options,
					completionHandler: callback
				)
			}
		}
	}

	/**
	[Metal Feature Set Tables ](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
	*/
	var supportsASTCCompressedTextures: Bool {
		metalDevice.supportsFamily(.apple2)
	}

	/**
	Compress to pixel format `astc_8x8_ldr`.

	See `convertToASTCTexture` for more info.
	*/
	func convertToASTCTexture(cgImage: CGImage) throws -> SendableTexture {
		let astcData = try cgImage.convertToData(
			withNewType: "org.khronos.astc",
			addOptions: ["kCGImagePropertyASTCBlockSize": 0x88]
		)

		return try metalDevice.convertToASTCTexture(isolated: self, astcData: astcData)
	}

	func convertAnimatedGIFToTextures(gifData: Data) -> ProgressableTask<Double, [SendableTexture?]> {
		ProgressableTask { progressContinuation in
			let imageSource = try CGImageSource.from(gifData)
			let supportsCompressedTextures = self.supportsASTCCompressedTextures

			var out = [SendableTexture?]()
			out.reserveCapacity(imageSource.count)

			for index in 0..<imageSource.count {
				try Task.checkCancellation()
				progressContinuation.yield(Double(index) / Double(imageSource.count))

				let image = try imageSource.createImage(atIndex: index)
				let newImage = supportsCompressedTextures ? try self.convertToASTCTexture(cgImage: image) : try await self.convertToTexture(cgImage: image)
				out.append(newImage)
			}

			return out
		}
	}

	struct DepthTextureSize: Hashable {
		let width: Int
		let height: Int
	}

	func getDepthTexture(width: Int, height: Int) throws -> MTLTexture {
		let size = DepthTextureSize(width: width, height: height)

		if let existingTexture = depthTextureCache[size] {
			return existingTexture
		}

		// Clean cache if it gets too large.
		if depthTextureCache.count >= 10 {
			depthTextureCache.removeAll()
		}

		let descriptor = MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: Self.depthAttachmentPixelFormat,
			width: width,
			height: height,
			mipmapped: false
		)
		descriptor.usage = .renderTarget
		descriptor.storageMode = .private

		guard let depthTexture = metalDevice.makeTexture(descriptor: descriptor) else {
			throw "Failed to create depth texture.".toError
		}

		depthTextureCache[size] = depthTexture

		return depthTexture
	}
}

extension MTLDevice {
	/**
	Use the compressed texture pixel Format [ASTC](https://www.khronos.org/opengl/wiki/ASTC_Texture_Compression)

	According to the [documentation](/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include/AppleTextureEncoder.h), `astc_8x8` is the smallest we can encode to with the built-in encoder, which is 2 bits per pixel.
	*/
	func convertToASTCTexture(
		isolated: isolated PreviewRenderer,
		astcData: Data
	) throws -> SendableTexture {
		let astcImage = try ASTCImage(data: astcData)
		let descriptor = try astcImage.descriptor()
		descriptor.storageMode = .managed
		descriptor.usage = [.shaderRead]

		guard let texture = makeTexture(descriptor: descriptor) else {
			throw ConvertToASTCTextureError.failedToCreateTextures
		}

		try astcImage.write(to: texture)
		return SendableTexture(texture: texture)
	}
}

enum ConvertToASTCTextureError: Error {
	case failedToCreateTextures
}

enum SendableTextureSource {
	case data(Data)
	case image(CGImage)
}

extension Data {
	/**
	If data holds `imageData`, this will convert to a texture suitable for `PreviewRenderer`.
	*/
	func convertToTexture() async throws -> SendableTexture {
		try await PreviewRenderer.shared.convertToTexture(data: self)
	}
}
