//
//  SettingsForFullPreview.swift
//  Gifski
//
//  Created by Michael Mulet on 4/23/25.
//

import Foundation
import CoreMedia
/**
 When creating a full preview you don't need the some setting such as loop or bounce, plus
 */
struct SettingsForFullPreview: Equatable {
	let conversion: GIFGenerator.Conversion
	let speed: Double
	let assetDuration: TimeInterval
	init(conversion: GIFGenerator.Conversion, speed: Double, duration assetDuration: TimeInterval) {
		self.speed = speed
		self.assetDuration = assetDuration
		var newConversion = conversion

		// Pad the time just a bit so that when adjusting the trim range the preview will have a frame generated after the trim operation completes. *Note* It's the same value as [PreBakedFrames.bugFixOffset](PreBakedFrames.bugFixOffset), but this is not the cause of that bug, the bug remains without this code.
		if let originalTimeRange = conversion.timeRange {
			let lowerBound = max(0, originalTimeRange.lowerBound - 0.1)
			let upperBound = min(assetDuration / speed, originalTimeRange.upperBound + 0.1)
			newConversion.timeRange = lowerBound...(upperBound)
		}
		newConversion.loop = .never
		newConversion.bounce = false
		self.conversion = newConversion
	}
	/**
	 See if the settings for fullPreview are the same (ignoring settings that do not affect fullPreview)
	 */
	func areTheSameBesidesTimeRange(_ settings: Self) -> Bool {
		var copyOld = self.conversion
		copyOld.timeRange = nil
		var copyNew = settings.conversion
		copyNew.timeRange = nil
		return copyNew == copyOld
	}
	/**
	 See if the time range of the new settings is a subset of the old settings
	 */
	func timeRangeContainsTimeRange(
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
}
