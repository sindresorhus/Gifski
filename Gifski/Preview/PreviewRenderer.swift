import Foundation
import Metal
import MetalKit

actor PreviewRenderer {
	private static var sharedRenderer: PreviewRenderer?

	static var shared: PreviewRenderer {
		get throws {
			if let sharedRenderer {
				return sharedRenderer
			}

			let renderer = try PreviewRenderer()
			sharedRenderer = renderer

			return renderer
		}
	}

	static let colorAttachmentPixelFormat = MTLPixelFormat.bgra8Unorm
	static let depthAttachmentPixelFormat = MTLPixelFormat.depth32Float

	private let context: PreviewRendererContext

	let metalDevice: MTLDevice
	let textureLoader: MTKTextureLoader
	var depthTextureCache = [DepthTextureSize: MTLTexture]()

	private init() throws {
		guard let metalDevice = MTLCreateSystemDefaultDevice() else {
			throw Error.noDevice
		}

		self.metalDevice = metalDevice

		guard metalDevice.supportsFamily(.common1) else {
			throw Error.unsupportedDevice
		}

		self.textureLoader = MTKTextureLoader(device: metalDevice)
		self.context = try PreviewRendererContext(metalDevice)
	}

	func renderOriginal(
		from videoFrame: SendableCVPixelBuffer,
		to outputFrame: SendableCVPixelBuffer,
	) throws {
		videoFrame.pixelBuffer.propagateAttachments(to: outputFrame.pixelBuffer)
		try videoFrame.pixelBuffer.copy(to: outputFrame.pixelBuffer)
	}

	func renderPreview(
		previewFrame: SendableTexture,
		outputFrame: SendableCVPixelBuffer,
		fragmentUniforms: CompositePreviewFragmentUniforms
	) async throws {
		outputFrame.pixelBuffer.setSRGBColorSpace()

		// Get a command buffer which will let us submit commands to the GPU.
		try await context.commandQueue.withCommandBuffer(isolated: self) { commandBuffer in
			// Convert our pixel buffer to a texture.
			let outputTexture = try context.textureCache.createTexture(
				from: outputFrame.pixelBuffer,
				pixelFormat: Self.colorAttachmentPixelFormat
			)

			// Remove isolation.
			let previewTexture = previewFrame.getTexture(isolated: self)

			// Setup the scale of our preview frame.
			let scale = SIMD2<Float>(
				x: outputTexture.texture.width > 0 ? Float(previewTexture.width.toDouble / outputTexture.texture.width.toDouble) : 1.0,
				y: outputTexture.texture.height > 0 ? Float(previewTexture.height.toDouble / outputTexture.texture.height.toDouble) : 1.0
			)

			// The render command encoder will create a render command (render on the GPU) (the command will run when the command buffer commits (which happens automatically at the end of this closure)).
			try commandBuffer.withRenderCommandEncoder(
				renderPassDescriptor: PreviewRendererContext.makeRenderPassDescriptor(
					outputTexture: outputTexture,
					depthTexture: try getDepthTexture(
						width: outputTexture.texture.width,
						height: outputTexture.texture.height
					)
				)
			) { renderEncoder in
				context.applyContext(to: renderEncoder)

				// Turn off back culling (this means we don't care what order triangles are wound, we can list the vertices in any order).
				renderEncoder.setCullMode(.none)

				// Send the texture to the fragment shader (which chooses the color of each pixel).
				renderEncoder.setFragmentTexture(previewTexture, index: 0)

				do {
					// Send data to the vertex shader. In this case, what scale the preview image is.
					var vertexUniforms = CompositePreviewVertexUniforms(scale: scale)

					renderEncoder.setVertexBytes(
						&vertexUniforms,
						length: MemoryLayout<CompositePreviewVertexUniforms>.stride,
						index: 0
					)
				}

				do {
					// Send our data to the fragment shader. Mostly about the checkerboard pattern.
					var fragmentUniforms = fragmentUniforms

					renderEncoder.setFragmentBytes(
						&fragmentUniforms,
						length: MemoryLayout<CompositePreviewFragmentUniforms>.stride,
						index: 0
					)
				}

				// Tell the encoder to draw. We want to draw 2 quads (one for the preview, one for the checkerboard pattern). The next  code to look at will be the vertex shader in `previewVertexShader`.
				renderEncoder.drawPrimitives(
					type: .triangle,
					vertexStart: 0,
					vertexCount: Int(VERTICES_PER_QUAD) * 2
				)
			}
		}
	}
}

extension PreviewRenderer {
	enum Error: Swift.Error {
		case noDevice
		case unsupportedDevice
		case noCommandQueue
		case failedToMakeSampler
		case failedToMakeTextureCache
		case libraryFailure
		case failedToMakeDepthStencilState
		case failedToMakeSendableTexture
	}
}

extension PreviewRenderer {
	/**
	After it is sent to `SendableCVPixelBuffer`, the `CVPixelBuffer` is only accessible to `PreviewRenderer`.
	*/
	final class SendableCVPixelBuffer: @unchecked Sendable {
		fileprivate let pixelBuffer: CVPixelBuffer

		init(pixelBuffer: CVPixelBuffer) {
			self.pixelBuffer = pixelBuffer
		}
	}
}
