import CoreImage
import AppKit
import CoreGraphics

struct PreviewRenderer {
	struct PreviewCheckerboardParameters: Equatable {
		let isDarkMode: Bool
		let videoBounds: CGRect
	}

	static func renderPreview(
		previewFrame: CVPixelBuffer,
		outputFrame: CVPixelBuffer,
		previewCheckerboardParams: PreviewCheckerboardParameters
	) async throws {
		let previewImage = CIImage(cvImageBuffer: previewFrame, options: [
			.colorSpace: outputFrame.colorSpace
		])
		try await renderPreview(previewImage: previewImage, outputFrame: outputFrame, previewCheckerboardParams: previewCheckerboardParams)
	}

	static func renderPreview(
		previewFrame: CGImage,
		outputFrame: CVPixelBuffer,
		previewCheckerboardParams: PreviewCheckerboardParameters
	) async throws {
		try await renderPreview(previewImage: CIImage(cgImage: previewFrame), outputFrame: outputFrame, previewCheckerboardParams: previewCheckerboardParams)
	}

	private static func renderPreview(
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

		context.render(
			result.cropped(to: outputRect),
			to: outputFrame,
			bounds: outputRect,
			colorSpace: outputFrame.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
		)
	}

	private static func createCheckerboard(
		outputRect: CGRect,
		uniforms: PreviewCheckerboardParameters
	) -> CIImage {
		guard let filter = CIFilter(name: "CICheckerboardGenerator") else {
			return CIImage.empty()
		}
		let scaleX = outputRect.width / uniforms.videoBounds.width
		let scaleY = outputRect.height / uniforms.videoBounds.height

		filter.setValue(Double(CheckerboardView.gridSize) * scaleX, forKey: "inputWidth")

		filter.setValue((uniforms.isDarkMode ? CheckerboardView.firstColorDark : CheckerboardView.firstColorLight).ciColor ?? .black, forKey: "inputColor0")
		filter.setValue((uniforms.isDarkMode ? CheckerboardView.secondColorDark : CheckerboardView.secondColorLight).ciColor ?? .white, forKey: "inputColor1")

		filter.setValue(
			CIVector(
				x: outputRect.midX + uniforms.videoBounds.midX * scaleX,
				y: outputRect.midY + uniforms.videoBounds.midY * scaleY
			),
			forKey: "inputCenter"
		)
		guard let output = filter.outputImage else {
			return CIImage.empty()
		}
		return output
	}
}
