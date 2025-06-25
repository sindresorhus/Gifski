import Foundation
import AVKit

extension CVPixelBuffer {
	enum ConvertToGIFError: Error {
		case failedToCreateCGContext
	}

	func convertToGIF(
		settings: SettingsForFullPreview
	) async throws -> Data {
		//  Not the fastest way to convert `CVPixelBuffer` to image, but the runtime of `GIFGenerator.convertOneFrame` is so much larger that optimizing this would be a waste
		let ciImage = CIImage(cvPixelBuffer: self)
		let ciContext = CIContext()

		guard
			let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
		else {
			throw ConvertToGIFError.failedToCreateCGContext
		}

		guard
			let croppedImage = settings.conversion.croppedImage(image: cgImage)
		else {
			throw GIFGenerator.Error.cropNotInBounds
		}

		return try await GIFGenerator.convertOneFrame(
			frame: croppedImage,
			dimensions: settings.conversion.croppedOutputDimensions,
			quality: max(0.1, settings.conversion.settings.quality),
			fast: true
		)
	}
}
