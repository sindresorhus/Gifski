import AppKit
import CoreGraphics
import CoreImage.CIFilterBuiltins

actor PreviewRenderer {
	static let shared = PreviewRenderer()

	struct PreviewCheckerboardParameters: Equatable {
		let isDarkMode: Bool
		let videoBounds: CGRect
	}

	static func renderOriginal(
		from videoFrame: CVPixelBuffer,
		to outputFrame: CVPixelBuffer,
	) async throws {
		try await shared.renderOriginal(from: videoFrame, to: outputFrame)
	}

	static func renderPreview(
		previewFrame: CVPixelBuffer,
		outputFrame: CVPixelBuffer,
		previewCheckerboardParams: PreviewCheckerboardParameters
	) async throws {
		try await shared.renderPreview(previewFrame: previewFrame, outputFrame: outputFrame, previewCheckerboardParams: previewCheckerboardParams)
	}

	static func renderPreview(
		previewFrame: CGImage,
		outputFrame: CVPixelBuffer,
		previewCheckerboardParams: PreviewCheckerboardParameters
	) async throws {
		try await shared.renderPreview(previewFrame: previewFrame, outputFrame: outputFrame, previewCheckerboardParams: previewCheckerboardParams)
	}


	private func renderPreview(
		previewFrame: CVPixelBuffer,
		outputFrame: CVPixelBuffer,
		previewCheckerboardParams: PreviewCheckerboardParameters
	) async throws {
		let previewImage = CIImage(
			cvPixelBuffer: previewFrame,
			options: outputFrame.colorSpace.map { space -> [CIImageOption: Any] in
				[
					.colorSpace: space
				]
			}
		)
		try await renderPreview(previewImage: previewImage, outputFrame: outputFrame, previewCheckerboardParams: previewCheckerboardParams)
	}

	private func renderPreview(
		previewFrame: CGImage,
		outputFrame: CVPixelBuffer,
		previewCheckerboardParams: PreviewCheckerboardParameters
	) async throws {
		try await renderPreview(previewImage: CIImage(cgImage: previewFrame), outputFrame: outputFrame, previewCheckerboardParams: previewCheckerboardParams)
	}

	private func renderOriginal(
		from videoFrame: CVPixelBuffer,
		to outputFrame: CVPixelBuffer,
	) throws {
		videoFrame.propagateAttachments(to: outputFrame)
		try videoFrame.copy(to: outputFrame)
	}

	private func renderPreview(
		previewImage: CIImage,
		outputFrame: CVPixelBuffer,
		previewCheckerboardParams: PreviewCheckerboardParameters
	) async throws {
		let context = CIContext()
		let outputWidth = Double(outputFrame.width)
		let outputHeight = Double(outputFrame.height)
		let outputSize = CGSize(width: outputWidth, height: outputHeight)
		let outputRect = CGRect(origin: .zero, size: outputSize)

		let checkerboard = createCheckerboard(
			outputRect: outputRect,
			uniforms: previewCheckerboardParams
		)

		let previewBounds = previewImage.extent

		let translationX = (outputWidth - previewBounds.width) / 2 - previewBounds.minX
		let translationY = (outputHeight - previewBounds.height) / 2 - previewBounds.minY

		let transform = CGAffineTransform.identity
			.translatedBy(x: translationX, y: translationY)

		let translatedPreview = previewImage.transformed(by: transform)
		let result = translatedPreview.composited(over: checkerboard)

		previewImage.pixelBuffer?.propagateAttachments(to: outputFrame)
		context.render(
			result.cropped(to: outputRect),
			to: outputFrame,
			bounds: outputRect,
			colorSpace: outputFrame.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
		)
	}

	private func createCheckerboard(
		outputRect: CGRect,
		uniforms: PreviewCheckerboardParameters
	) -> CIImage {
		let scaleX = outputRect.width / uniforms.videoBounds.width
		let scaleY = outputRect.height / uniforms.videoBounds.height

		let checkerBoardGenerator = CIFilter.checkerboardGenerator()
		checkerBoardGenerator.setDefaults()
		checkerBoardGenerator.center = .init(
			x: outputRect.midX + uniforms.videoBounds.midX * scaleX,
			y: outputRect.midY + uniforms.videoBounds.midY * scaleY
		)
		checkerBoardGenerator.color0 = (uniforms.isDarkMode ? CheckerboardViewConstants.firstColorDark : CheckerboardViewConstants.firstColorLight).ciColor ?? .black
		checkerBoardGenerator.color1 = (uniforms.isDarkMode ? CheckerboardViewConstants.secondColorDark : CheckerboardViewConstants.secondColorLight).ciColor ?? .white
		checkerBoardGenerator.width = Float(Float(CheckerboardViewConstants.gridSize) * Float(scaleX))
		checkerBoardGenerator.sharpness = 1

		guard let output = checkerBoardGenerator.outputImage else {
			return CIImage.empty()
		}
		return output
	}
}
