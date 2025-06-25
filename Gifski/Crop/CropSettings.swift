import Foundation
import AVKit

protocol CropSettings {
	var dimensions: (width: Int, height: Int)? { get }
	var crop: CropRect? { get }
}

extension GIFGenerator.Conversion: CropSettings {}

extension CropSettings {
	/**
	We don't use `croppedOutputDimensions` here because the `CGImage` source may have a different size. We use the size directly from the image.

	If the rect parameter defines an area that is not in the image, it returns nil: https://developer.apple.com/documentation/coregraphics/cgimage/1454683-cropping
	*/
	func croppedImage(image: CGImage) -> CGImage? {
		guard let crop else {
			return image
		}

		return image.cropping(to: crop.unnormalize(forDimensions: (image.width, image.height)))
	}

	var croppedOutputDimensions: (width: Int, height: Int)? {
		guard let crop else {
			return dimensions
		}

		guard let dimensions else {
			return nil
		}

		let cropInPixels = crop.unnormalize(forDimensions: dimensions)

		return (
			cropInPixels.width.toIntAndClampingIfNeeded,
			cropInPixels.height.toIntAndClampingIfNeeded
		)
	}
}
