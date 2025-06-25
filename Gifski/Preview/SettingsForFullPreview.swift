import Foundation
import CoreMedia
import AVFoundation



/**
 When creating a full preview you don't need the some setting such as loop or bounce, plus it has additional info like assetDuration and speed.
 */
struct SettingsForFullPreview: Equatable, Sendable {
	let conversion: SendableConversion
	let speed: Double
	let assetDuration: TimeInterval
	let framesPerSecondsWithoutSpeedAdjustment: Int
	init(conversion: GIFGenerator.Conversion, speed: Double, framesPerSecondsWithoutSpeedAdjustment: Int, duration assetDuration: TimeInterval) {
		self.speed = speed
		self.framesPerSecondsWithoutSpeedAdjustment = framesPerSecondsWithoutSpeedAdjustment
		self.assetDuration = assetDuration
		self.conversion = SendableConversion(conversion: conversion)
	}

	func areSettingsDifferentEnoughForANewFullPreview(newSettings: Self, areCurrentlyGenerating: Bool, oldRequestID: Int, newRequestID: Int) -> Bool {
		guard speed == newSettings.speed else {
			return true
		}
		if self == newSettings {
			newRequestID.p("Skipping - Same as \(oldRequestID)")
			return false
		}
		if !areCurrentlyGenerating,
		   areTheSameBesidesTimeRange(newSettings),
		   timeRangeContainsTimeRange(of: newSettings) {
			newRequestID.p("Skipping - Same as ready \(oldRequestID)")
			return false
		}
		newRequestID.p("Different than \(oldRequestID)")
		return true
	}

	/**
	 See if the settings for fullPreview are the same (ignoring settings that do not affect fullPreview)
	 */
	private func areTheSameBesidesTimeRange(_ settings: Self) -> Bool {
		self.conversion.settings == settings.conversion.settings
	}
	/**
	 See if the time range of the new settings is a subset of the old settings
	 */
	private func timeRangeContainsTimeRange(
		of newSettings: Self,
	) -> Bool {
		guard let oldTimeRange = self.conversion.timeRange else {
			/**
			 nil means the entire duration, so all sets are subset of the range
			 */
			return true
		}
		guard let newTimeRange = newSettings.conversion.timeRange else {
			/**
			 old is not full, but new is full, thus it is not a subset
			 */
			return false
		}
		return oldTimeRange.contains(newTimeRange)
	}

	struct SendableConversion: ReflectiveHashable, Sendable, CropSettings {
		let timeRange: ClosedRange<Double>?
		let settings: ConversionSettings

		var dimensions: (width: Int, height: Int)? {
			settings.dimensions
		}
		var crop: CropRect? {
			settings.crop
		}

		struct ConversionSettings: ReflectiveHashable, Sendable {
			let sourceURL: URL
			let quality: Double
			let dimensions: (width: Int, height: Int)?
			let frameRate: Int?
			let crop: CropRect?
			var loop: Gifski.Loop {
				.never
			}
			var bounce: Bool {
				false
			}
		}

		init(conversion: GIFGenerator.Conversion){
			timeRange = conversion.timeRange
			settings = .init(
				sourceURL: conversion.sourceURL,
				quality: conversion.quality,
				dimensions: conversion.dimensions,
				frameRate: conversion.frameRate,
				crop: conversion.crop
			)
		}

		func toConversion(asset: AVAsset) -> GIFGenerator.Conversion {
			GIFGenerator.Conversion(
				asset: asset,
				sourceURL: settings.sourceURL,
				timeRange: timeRange,
				quality: settings.quality,
				dimensions: settings.dimensions,
				frameRate: settings.frameRate,
				loop: settings.loop,
				bounce: settings.bounce,
				crop: settings.crop
			)
		}
	}
}
