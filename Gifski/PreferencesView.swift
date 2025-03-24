//
//  PreferencesView.swift
//  Gifski
//
//  Created by Michael Mulet on 3/23/25.

import SwiftUI
import AVFoundation


struct PreferencesView: View {
	@Default(.quickOutputQuality) private var outputQuality
	@Default(.quickBounceGIF) private var bounceGIF
	@Default(.quickOutputFPS) private var frameRate
	@Default(.quickLoopGIF) private var loopGIF
	@Default(.quickOutputSpeed) private var outputSpeed
	@Default(.quickLoopCount) private var loopCount
	@Default(.quickResize) private var outputResize

	var body: some View {
		VStack {
			Text("Preferences")
				.font(.headline)
			Text("Quick Action Settings:")
			Text("All the settings here will be used for the Quick Action 'Quick Convert to GIF with Gifski' in Finder")
			EditControls(
				canEditDimensions: false,
				metadata: .init(
					dimensions: .init(widthHeight: 1),
					duration: .seconds(1),
					frameRate: 50,
					fileSize: 1
				),
				resizableDimensions: .constant(.percent(1.0, originalSize: .init(widthHeight: 1.0))),
				loopCount: $loopCount,
				outputFPS: $frameRate,
				outputSpeed: $outputSpeed,
				outputQuality: $outputQuality,
				loopGIF: $loopGIF,
				bounceGIF: $bounceGIF,
				outputResize: $outputResize
			)
		}
		.padding()
		.frame(width: 760, height: 640)
	}
}
