import Foundation
import AVKit

protocol CropSettings {
	var dimensions: (width: Int, height: Int)? { get }
	var outputDimensions: (width: Int, height: Int)? { get }
	var trackPreferredTransform: CGAffineTransform? { get }
	var crop: CropRect? { get }
}

extension GIFGenerator.Conversion: CropSettings {}

extension CropSettings {
	var outputDimensions: (width: Int, height: Int)? {
		nil
	}

	/**
	We don't use `croppedOutputDimensions` here because the `CGImage` source may have a different size. We use the size directly from the image.

	If the rect parameter defines an area that is not in the image, it returns nil: https://developer.apple.com/documentation/coregraphics/cgimage/1454683-cropping
	*/
	func croppedImage(image: CGImage) -> CGImage? {
		guard crop != nil else {
			return image
		}
		let transformedCrop = unnormalizedCropRect(sizeInPreferredTransformationSpace: .init(width: image.width, height: image.height))
		return image.cropping(to: transformedCrop)
	}

	/**
	Returns the unnormalized crop rect for an image that is already in the preferred transform space (i.e., already rotated).

	Since `AVAssetImageGenerator.appliesPreferredTrackTransform = true` and the preview manually applies the transform, images are always pre-rotated. The crop rect (which is defined in rotated space via the UI) can be applied directly.
	*/
	func unnormalizedCropRect(sizeInPreferredTransformationSpace preferredSize: CGSize) -> CGRect {
		guard let cropRect = crop else {
			return .init(origin: .zero, size: preferredSize)
		}
		return cropRect.unnormalize(forDimensions: preferredSize)
	}

	var croppedOutputDimensions: (width: Int, height: Int)? {
		if let outputDimensions {
			return outputDimensions
		}

		guard crop != nil else {
			return dimensions
		}

		guard let dimensions else {
			return nil
		}

		let outputDimensions = unnormalizedCropRect(sizeInPreferredTransformationSpace: .init(width: dimensions.width, height: dimensions.height))
		return (
			outputDimensions.width.toIntAndClampingIfNeeded,
			outputDimensions.height.toIntAndClampingIfNeeded
		)
	}
}
