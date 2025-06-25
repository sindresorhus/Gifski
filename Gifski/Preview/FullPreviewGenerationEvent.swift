import Foundation
import AVFoundation
import Metal

/**
Events that will be emitted by `PreviewStream`, which represent the state or a generation request.
*/
struct FullPreviewGenerationEvent: Equatable, Sendable {
	let requestID: Int
	private let state: State
}

extension FullPreviewGenerationEvent {
	var canShowPreview: Bool {
		switch state {
		case .empty, .cancelled:
			false
		case .generating, .ready:
			true
		}
	}

	var errorMessage: String? {
		switch state {
		case .empty(error: let error):
			error
		case .generating, .ready, .cancelled:
			nil
		}
	}

	var progress: Double {
		switch state {
		case .empty, .cancelled:
			0.0
		case .generating(let generating):
			generating.progress
		case .ready:
			1.0
		}
	}

	var isGenerating: Bool {
		switch state {
		case .generating:
			true
		case .empty, .ready, .cancelled:
			false
		}
	}

	/**
	- Returns: The texture that represents the current preview frame, or `nil` if there is no preview for this frame.
	*/
	func getPreviewFrame(
		originalFrame: CVPixelBuffer,
		compositionTime: CMTime
	) async throws -> SendableTexture? {
		switch state {
		case .empty, .cancelled:
			nil
		case .generating(let generating):
			try await originalFrame.convertToGIF(settings: generating.settings).convertToTexture()
		case .ready(let fullPreview):
			try fullPreview.getGIF(at: compositionTime)
		}
	}

	/**
	Check if we can skip generating a full preview based on the last state.

	- Returns: `true` if a new generation is required, `false` otherwise.
	*/
	func isNecessaryToCreateNewFullPreview(
		newSettings: SettingsForFullPreview,
		newRequestID: Int
	) -> Bool {
		settings?.areSettingsDifferentEnoughForANewFullPreview(
			newSettings: newSettings,
			areCurrentlyGenerating: isGenerating,
			oldRequestID: requestID,
			newRequestID: newRequestID
		) ?? true
	}

	private var settings: SettingsForFullPreview? {
		switch state {
		case .empty, .cancelled:
			nil
		case .generating(let generating):
			generating.settings
		case .ready(let fullPreview):
			fullPreview.settings
		}
	}
}

extension FullPreviewGenerationEvent {
	static let initialState = Self(requestID: -1, state: .initialState)

	static func empty(error: String? = nil, requestID: Int) -> Self {
		.init(requestID: requestID, state: .empty(error: error))
	}

	static func cancelled(requestID: Int) -> Self {
		.init(requestID: requestID, state: .cancelled)
	}

	static func generating(
		settings: SettingsForFullPreview,
		progress: Double,
		requestID: Int
	) -> Self {
		.init(
			requestID: requestID,
			state: .generating(.init(settings: settings, progress: progress))
		)
	}

	static func ready(
		settings: SettingsForFullPreview,
		gifData: [SendableTexture?],
		requestID: Int
	) -> Self {
		.init(
			requestID: requestID,
			state: .ready(.init(settings: settings, gifData: gifData))
		)
	}
}

extension FullPreviewGenerationEvent {
	private enum State: Equatable {
		case empty(error: String?)
		case cancelled
		case generating(Generating)
		case ready(FullPreview)

		static let initialState = Self.empty(error: nil)

		func sameCase(as other: Self) -> Bool {
			switch (self, other) {
			case (.empty, .empty),
				(.cancelled, .cancelled),
				(.generating, .generating),
				(.ready, .ready):
				true
			default:
				false
			}
		}
	}

	private struct Generating: Equatable {
		let settings: SettingsForFullPreview
		let progress: Double
	}
}

extension FullPreviewGenerationEvent {
	fileprivate struct FullPreview {
		let settings: SettingsForFullPreview
		let gifData: [SendableTexture?]
	}
}

extension FullPreviewGenerationEvent.FullPreview: Equatable {
	/**
	They are equal if the settings that led to the creation of a full preview are equal.
	*/
	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.settings == rhs.settings
	}
}

extension FullPreviewGenerationEvent.FullPreview {
	enum Error: Swift.Error {
		case failedToGetGIFFrame
	}

	func getGIF(at compositionTime: CMTime) throws(Error) -> SendableTexture {
		guard let image = gifData[getCurrentGIFIndex(at: compositionTime)] else {
			throw .failedToGetGIFFrame
		}

		return image
	}

	private func getCurrentGIFIndex(at compositionTime: CMTime) -> Int {
		let timeRangeInOriginalSpeed = settings.conversion.timeRange ?? (0...settings.assetDuration)

		let gifTimeInOriginalSpeed = originalCompositionTime(from: compositionTime) - timeRangeInOriginalSpeed.lowerBound
		let adjustedFramesPerSecond = Double(settings.framesPerSecondsWithoutSpeedAdjustment) / settings.speed

		return Int(floor(gifTimeInOriginalSpeed * adjustedFramesPerSecond))
			.clamped(from: 0, to: gifData.count - 1)
	}

	/**
	Time that has been scaled.

	The composition will speed up or slow down the time. For example, if the player is at 2x speed. This struct takes the reported time of 0.5 and multiplies it by 2, to get 1 second of the original time in the composition.
	*/
	private func originalCompositionTime(from reportedCompositionTime: CMTime) -> Double {
		reportedCompositionTime.seconds * settings.speed
	}
}

extension FullPreviewGenerationEvent: PreviewComparable {
	/**
	`PreviewComparable` compares if the image on the screen is visually different between the two states.
	*/
	static func ~= (lhs: Self, rhs: Self) -> Bool {
		// If we have two settings, compare if the settings are the same.
		if let lhsSettings = lhs.settings {
			if let rhsSettings = rhs.settings {
				return lhs.state.sameCase(as: rhs.state) && lhsSettings == rhsSettings
			}

			return false
		}

		// lhs is `no preview`, so if rhs has `settings` we know we are different.
		if rhs.settings != nil {
			return false
		}

		// lhs has `no preview` and rhs has `no preview` so they are the same.
		return true
	}
}
