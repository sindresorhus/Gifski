import CoreImage
import CoreGraphics

struct PreviewRenderer {
	struct FragmentUniforms: Equatable {
		var videoBounds: SIMD4<Float>
		var firstColor: SIMD4<Float>
		var secondColor: SIMD4<Float>
		var gridSize: SIMD4<Int>

		init(isDarkMode: Bool, videoBounds: CGRect) {
			self.videoBounds = .init(
				x: Float(videoBounds.minX),
				y: Float(videoBounds.minY),
				z: Float(videoBounds.width),
				w: Float(videoBounds.height)
			)
			self.gridSize = .init(x: CheckerboardView.gridSize, y: 0, z: 0, w: 0)
			self.firstColor = (isDarkMode ? CheckerboardView.firstColorDark : CheckerboardView.firstColorLight).asLinearSIMD4 ?? .zero
			self.secondColor = (isDarkMode ? CheckerboardView.secondColorDark : CheckerboardView.secondColorLight).asLinearSIMD4 ?? .zero
		}
	}

	static func renderPreview(
		previewFrame: CVPixelBuffer,
		outputFrame: CVPixelBuffer,
		fragmentUniforms: FragmentUniforms
	) async throws {
		let context = CIContext()
		let outputWidth = Double(CVPixelBufferGetWidth(outputFrame))
		let outputHeight = Double(CVPixelBufferGetHeight(outputFrame))
		let outputSize = CGSize(width: outputWidth, height: outputHeight)
		let outputRect = CGRect(origin: .zero, size: outputSize)

		let checkerboard = createCheckerboard(
			size: outputSize,
			gridSize: fragmentUniforms.gridSize.x,
			firstColor: fragmentUniforms.firstColor.ciColor,
			secondColor: fragmentUniforms.secondColor.ciColor
		)

		let previewImage = CIImage(cvPixelBuffer: previewFrame)
		let previewBounds = previewImage.extent
		let scale = min(
			outputWidth / previewBounds.width,
			outputHeight / previewBounds.height
		)

		let scaledSize = CGSize(
			width: previewBounds.width * scale,
			height: previewBounds.height * scale
		)

		let centeredRect = CGRect(
			x: (outputWidth - scaledSize.width) / 2,
			y: (outputHeight - scaledSize.height) / 2,
			width: scaledSize.width,
			height: scaledSize.height
		)

		let transform = CGAffineTransform.identity
			.translatedBy(x: centeredRect.minX, y: centeredRect.minY)
			.scaledBy(x: scale, y: scale)

		let scaledPreview = previewImage.transformed(by: transform)
		let result = scaledPreview.composited(over: checkerboard)

		try context.render(
			result.cropped(to: outputRect),
			to: outputFrame,
			bounds: outputRect,
			colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
		)
	}

	static func renderPreview(
		previewFrame: CGImage,
		outputFrame: CVPixelBuffer,
		fragmentUniforms: FragmentUniforms
	) async throws {
		let context = CIContext()
		let outputWidth = Double(CVPixelBufferGetWidth(outputFrame))
		let outputHeight = Double(CVPixelBufferGetHeight(outputFrame))
		let outputSize = CGSize(width: outputWidth, height: outputHeight)
		let outputRect = CGRect(origin: .zero, size: outputSize)

		let checkerboard = createCheckerboard(
			size: outputSize,
			gridSize: fragmentUniforms.gridSize.x,
			firstColor: fragmentUniforms.firstColor.ciColor,
			secondColor: fragmentUniforms.secondColor.ciColor
		)

		let previewImage = CIImage(cgImage: previewFrame)
		let previewBounds = previewImage.extent
		let scale = min(
			outputWidth / previewBounds.width,
			outputHeight / previewBounds.height
		)

		let scaledSize = CGSize(
			width: previewBounds.width * scale,
			height: previewBounds.height * scale
		)

		let centeredRect = CGRect(
			x: (outputWidth - scaledSize.width) / 2,
			y: (outputHeight - scaledSize.height) / 2,
			width: scaledSize.width,
			height: scaledSize.height
		)

		let transform = CGAffineTransform.identity
			.translatedBy(x: centeredRect.minX, y: centeredRect.minY)
			.scaledBy(x: scale, y: scale)

		let scaledPreview = previewImage.transformed(by: transform)
		let result = scaledPreview.composited(over: checkerboard)

		try context.render(
			result.cropped(to: outputRect),
			to: outputFrame,
			bounds: outputRect,
			colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
		)
	}

	private static func createCheckerboard(
		size: CGSize,
		gridSize: Int,
		firstColor: CIColor,
		secondColor: CIColor
	) -> CIImage {
		guard let filter = CIFilter(name: "CICheckerboardGenerator") else {
			return CIImage.empty()
		}

		filter.setValue(Double(gridSize), forKey: "inputWidth")
		filter.setValue(firstColor, forKey: "inputColor0")
		filter.setValue(secondColor, forKey: "inputColor1")
		filter.setValue(
			CIVector(x: size.width / 2, y: size.height / 2),
			forKey: "inputCenter"
		)

		guard let output = filter.outputImage else {
			return CIImage.empty()
		}

		return output.cropped(to: CGRect(origin: .zero, size: size))
	}
}

extension SIMD4 where Scalar == Float {
	var ciColor: CIColor {
		CIColor(red: Double(x), green: Double(y), blue: Double(z), alpha: Double(w))
	}
}
