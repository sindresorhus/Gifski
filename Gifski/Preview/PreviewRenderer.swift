//
//  PreviewRenderer.swift
//  Gifski
//
//  Created by Michael Mulet on 4/22/25.
//

import Foundation
import Metal
import MetalKit

/**
 Use its static function [renderPreview](PreviewRenderer.renderPreview) to render the preview to a provided buffer
 */
struct PreviewRenderer {
	/**
	 Render the preview to the outputFrame
	 */
	static func renderPreview(previewFrame: LockedCVPixelBuffer, originalFrame: LockedCVPixelBuffer, outputFrame: inout ReadWriteableCVPixelBuffer) async throws {
		try await shared.get().drawFrame(previewFrame: previewFrame, originalFrame: originalFrame, outputFrame: &outputFrame)
	}
	/**
	 Render the preview to the output frame based on a (CGImage)[CGImage]
	 */
	static func renderPreview(previewFrame: CGImage, originalFrame: LockedCVPixelBuffer, outputFrame: inout ReadWriteableCVPixelBuffer) async throws {
		try await shared.get().drawFrame(previewFrame: previewFrame, originalFrame: originalFrame, outputFrame: &outputFrame)
	}

	static func renderPreview(previewFrame: MTLTexture, originalFrame: LockedCVPixelBuffer, outputFrame: inout ReadWriteableCVPixelBuffer) async throws {
		try await shared.get().drawGifFrameInCenterMetal(previewTexture: previewFrame, originalFrame: originalFrame, outputFrame: &outputFrame)
	}

	static func convertToTexture(cgImage: CGImage) async throws -> MTLTexture {
		try await shared.get().convertToTexture(cgImage: cgImage)
	}


	private static var shared = Result {
		try Self()
	}

	private func convertToTexture(cgImage: CGImage) async throws -> MTLTexture {
		try await textureLoader.newTexture(cgImage: cgImage, options: [
			.SRGB: false
		])
	}

	private struct VertexUniforms {
		var scale: SIMD2<Float>
	}

	private struct FragmentUniforms {
		var blurStrength: Float
	}

	private let metalDevice: MTLDevice
	private let commandQueue: MTLCommandQueue
	private let pipelineState: MTLRenderPipelineState
	private let samplerState: MTLSamplerState
	private let textureCache: CVMetalTextureCache
	private let previewTextureCache: CVMetalTextureCache
	private let originalTextureCache: CVMetalTextureCache
	private let textureLoader: MTKTextureLoader

	private init() throws {
		guard let metalDevice = MTLCreateSystemDefaultDevice() else {
			throw RenderError.noDevice
		}
		self.metalDevice = metalDevice
		guard let commandQueue = metalDevice.makeCommandQueue() else {
			throw RenderError.noCommandQueue
		}
		self.commandQueue = commandQueue

		guard let library = metalDevice.makeDefaultLibrary(),
			  let meshFunction = library.makeFunction(name: "previewMeshShader"),
			  let fragmentFunction = library.makeFunction(name: "previewFragment") else {
			throw RenderError.libraryFailure
		}

		let pipelineDescriptor = MTLMeshRenderPipelineDescriptor()
		pipelineDescriptor.meshFunction = meshFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
		let (pipelineState, _ ) = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor, options: [])
		self.pipelineState = pipelineState

		let samplerDescriptor = MTLSamplerDescriptor()
		samplerDescriptor.minFilter = .linear
		samplerDescriptor.magFilter = .linear
		samplerDescriptor.sAddressMode = .clampToEdge
		samplerDescriptor.tAddressMode = .clampToEdge

		guard let samplerState = metalDevice.makeSamplerState(descriptor: samplerDescriptor) else {
			throw RenderError.failedToMakeSampler
		}
		self.samplerState = samplerState

		var textureCache: CVMetalTextureCache?
		CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &textureCache)
		var previewTextureCache: CVMetalTextureCache?
		CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &previewTextureCache)

		var originalTextureCache: CVMetalTextureCache?
		CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &originalTextureCache)

		guard let textureCache,
			  let previewTextureCache,
			  let originalTextureCache
		else {
			throw RenderError.failedToMakeTextureCache
		}
		self.textureCache = textureCache
		self.previewTextureCache = previewTextureCache
		self.originalTextureCache = originalTextureCache

		self.textureLoader = MTKTextureLoader(device: metalDevice)
	}

	private func drawFrame(
		previewFrame: LockedCVPixelBuffer,
		originalFrame: LockedCVPixelBuffer,
		outputFrame: inout ReadWriteableCVPixelBuffer
	) async throws {
		let gifTexture = try Texture.createFromImage(image: previewFrame, cache: previewTextureCache)
		try await drawGifFrameInCenterMetal(previewTexture: gifTexture.tex, originalFrame: originalFrame, outputFrame: &outputFrame)
	}

	private func drawFrame(
		previewFrame: CGImage,
		originalFrame: LockedCVPixelBuffer,
		outputFrame: inout ReadWriteableCVPixelBuffer
	) async throws {
		let texture = try await convertToTexture(cgImage: previewFrame)

		try await drawGifFrameInCenterMetal(previewTexture: texture, originalFrame: originalFrame, outputFrame: &outputFrame)
	}

	private func drawGifFrameInCenterMetal(
		previewTexture: MTLTexture,
		originalFrame: LockedCVPixelBuffer,
		outputFrame: inout ReadWriteableCVPixelBuffer
	) async throws {
		let originalTexture = try Texture.createFromImage(image: originalFrame, cache: originalTextureCache)
		let outputTexture = try Texture.createFromImage(image: outputFrame, cache: textureCache)
		guard let commandBuffer = commandQueue.makeCommandBuffer() else {
			throw RenderError.failedToCreateCommandBuffer
		}

		let renderPassDescriptor = MTLRenderPassDescriptor()
		renderPassDescriptor.colorAttachments[0].texture = outputTexture.tex
		renderPassDescriptor.colorAttachments[0].loadAction = .clear
		renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
		renderPassDescriptor.colorAttachments[0].storeAction = .store

		guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
			throw RenderError.failedToMakeRenderCommandEncoder
		}

		renderEncoder.setRenderPipelineState(pipelineState)
		renderEncoder.setCullMode(.none)

		renderEncoder.setFragmentTexture(previewTexture, index: 0)
		renderEncoder.setFragmentTexture(originalTexture.tex, index: 1)
		renderEncoder.setFragmentSamplerState(samplerState, index: 0)

		var uniforms = VertexUniforms(scale: .init(x: Float(previewTexture.width.toDouble / originalTexture.tex.width.toDouble), y: Float(previewTexture.height.toDouble / originalTexture.tex.height.toDouble)))
		renderEncoder.setMeshBytes(&uniforms, length: MemoryLayout<VertexUniforms>.size, index: 0)

		var fragmentUniforms = FragmentUniforms(blurStrength: 20.5)
		renderEncoder.setFragmentBytes(&fragmentUniforms, length: MemoryLayout<FragmentUniforms>.size, index: 0)

		renderEncoder.drawMeshThreadgroups(
			MTLSize(width: 1, height: 1, depth: 1),
			threadsPerObjectThreadgroup: MTLSize(width: 1, height: 1, depth: 1),
			threadsPerMeshThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
		)

		renderEncoder.endEncoding()

		await withCheckedContinuation { continuation in
			commandBuffer.addCompletedHandler { _ in
				continuation.resume()
			}
			commandBuffer.commit()
		}
		guard commandBuffer.status == .completed else {
			throw RenderError.failedToRender
		}
	}


	/**
	 Need to keep a strong reference to the CVMetalTexture until the GPU command completes, this struct ensures that the CVMetalTexture is not garbage collected as long as the MTLTexture is around [see](https://developer.apple.com/documentation/corevideo/cvmetaltexturecachecreatetexturefromimage(_:_:_:_:_:_:_:_:_:))
	 */
	private struct Texture {
		private let cv: CVMetalTexture
		let tex: MTLTexture
		init(cv: CVMetalTexture, tex: MTLTexture) {
			self.cv = cv
			self.tex = tex
		}
		static func createFromImage(image: LockedCVPixelBuffer, cache: CVMetalTextureCache) throws -> Self {
			let videoWidth = CVPixelBufferGetWidth(image.buf)
			let videoHeight = CVPixelBufferGetHeight(image.buf)

			var cv: CVMetalTexture?
			guard
				CVMetalTextureCacheCreateTextureFromImage(
					nil,
					cache,
					image.buf,
					nil,
					.bgra8Unorm,
					videoWidth,
					videoHeight,
					0,
					&cv
				) == kCVReturnSuccess,
				let cv,
				let tex = CVMetalTextureGetTexture(cv)
			else {
				throw RenderError.failedToCreateTextures
			}
			return .init(cv: cv, tex: tex)
		}
	}


	enum RenderError: Error {
		case noDevice
		case noCommandQueue
		case failedToMakeBuffer
		case failedToMakeSampler
		case failedToMakeTextureCache
		case libraryFailure
		case invalidState
		case failedToCreateTextures
		case failedToCreateCommandBuffer
		case failedToMakeRenderCommandEncoder
		case failedToRender
	}
}
