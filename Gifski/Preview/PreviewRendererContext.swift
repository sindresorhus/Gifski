import Foundation
import MetalKit

/**
The static state context we setup at runtime and use later.
*/
struct PreviewRendererContext {
	private let pipelineState: MTLRenderPipelineState
	private let depthStencilState: MTLDepthStencilState
	private let samplerState: MTLSamplerState

	let commandQueue: MTLCommandQueue
	let textureCache: CVMetalTextureCache

	init(_ metalDevice: MTLDevice) throws {
		guard let commandQueue = metalDevice.makeCommandQueue() else {
			throw PreviewRenderer.Error.noCommandQueue
		}

		self.pipelineState = try Self.setupPipelineState(metalDevice)
		self.samplerState = try Self.setupSamplerState(metalDevice)
		self.depthStencilState = try Self.setupDepthStencilState(metalDevice)
		self.commandQueue = commandQueue
		self.textureCache = try Self.setupTextureCache(metalDevice)
	}

	/**
	Set the render command encoder to use the context we have created.
	*/
	func applyContext(to renderCommandEncoder: MTLRenderCommandEncoder) {
		// Set up the depth buffer.
		renderCommandEncoder.setDepthStencilState(depthStencilState)

		// Set up the actual render.
		renderCommandEncoder.setRenderPipelineState(pipelineState)

		// Set up the sampler (allow us to read from the texture).
		renderCommandEncoder.setFragmentSamplerState(samplerState, index: 0)
	}

	/**
	The render pipeline sets up our shaders in `compositePreview.metal` and sets up to write to a color attachment with a depth buffer.
	*/
	private static func setupPipelineState(_ metalDevice: MTLDevice) throws -> MTLRenderPipelineState {
		guard
			let library = metalDevice.makeDefaultLibrary(),
			let vertexFunction = library.makeFunction(name: "previewVertexShader"),
			let fragmentFunction = library.makeFunction(name: "previewFragment")
		else {
			throw PreviewRenderer.Error.libraryFailure
		}

		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction

		// This is the output of the render pass.
		pipelineDescriptor.colorAttachments[0].pixelFormat = PreviewRenderer.colorAttachmentPixelFormat

		// This is a texture which stores the "depth" of each pixel. It is used to decide whether a pixel will occlude another pixel.
		pipelineDescriptor.depthAttachmentPixelFormat = PreviewRenderer.depthAttachmentPixelFormat

		return try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
	}

	/**
	Create a render pass descriptor to match our pipeline. Here we pass in the actual data (i.e. the textures).
	*/
	static func makeRenderPassDescriptor(
		outputTexture: CVMetalTextureRefeference,
		depthTexture: MTLTexture
	) -> MTLRenderPassDescriptor {
		let renderPassDescriptor = MTLRenderPassDescriptor()

		renderPassDescriptor.colorAttachments[0].texture = outputTexture.texture

		// before the render pass clear the output to the clear color
		renderPassDescriptor.colorAttachments[0].loadAction = .clear
		// which in this case is black
		renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
		// after the render pass write to the output texture
		renderPassDescriptor.colorAttachments[0].storeAction = .store

		renderPassDescriptor.depthAttachment.texture = depthTexture
		// before render pass clear the depth texture to the clear depth
		renderPassDescriptor.depthAttachment.loadAction = .clear
		// which is 1.0, since our `depthCompareFunction` is `.less` anything less than `1.0` will be drawn
		renderPassDescriptor.depthAttachment.clearDepth = 1.0
		// after render pass we don't care what happens to the depth texture (it has served its purpose)
		renderPassDescriptor.depthAttachment.storeAction = .dontCare

		return renderPassDescriptor
	}

	/**
	The sampler is how we retrieve texture data inside the shader. We set it up such that we will linearly interpret all pixel data.
	*/
	private static func setupSamplerState(_ metalDevice: MTLDevice) throws(PreviewRenderer.Error) -> MTLSamplerState {
		let samplerDescriptor = MTLSamplerDescriptor()

		// Linearly interpolate colors between texels.
		samplerDescriptor.minFilter = .linear
		samplerDescriptor.magFilter = .linear

		// If we sample outside of our texture (0-1) use the same color as the edge.
		samplerDescriptor.sAddressMode = .clampToEdge
		samplerDescriptor.tAddressMode = .clampToEdge

		guard let samplerState = metalDevice.makeSamplerState(descriptor: samplerDescriptor) else {
			throw .failedToMakeSampler
		}

		return samplerState
	}

	/**
	Set up a depth buffer so that the preview will appear above the checkerboard pattern on all devices.
	*/
	private static func setupDepthStencilState(
		_ metalDevice: MTLDevice
	) throws(PreviewRenderer.Error) -> MTLDepthStencilState {
		let depthStencilDescriptor = MTLDepthStencilDescriptor()

		// For each pixel, if the depth is less than the current depth buffer, then draw, other wise don't draw.
		depthStencilDescriptor.depthCompareFunction = .less

		// Each time you do draw (it is less than current depth buffer), store the current depth in the depth buffer.
		depthStencilDescriptor.isDepthWriteEnabled = true

		guard let depthStencilState = metalDevice.makeDepthStencilState(descriptor: depthStencilDescriptor) else {
			throw .failedToMakeDepthStencilState
		}

		return depthStencilState
	}

	/**
	Set up a texture cache to write out output pixel buffer to.
	*/
	private static func setupTextureCache(
		_ metalDevice: MTLDevice
	) throws(PreviewRenderer.Error) -> CVMetalTextureCache {
		var textureCache: CVMetalTextureCache?
		CVMetalTextureCacheCreate(nil, nil, metalDevice, nil, &textureCache)

		guard let textureCache else {
			throw .failedToMakeTextureCache
		}

		return textureCache
	}
}
