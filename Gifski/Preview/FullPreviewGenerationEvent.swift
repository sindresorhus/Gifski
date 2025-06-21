import Foundation
import AVFoundation
import Metal

/**
 Events that will be emitted by the PreviewStream, they represent the state or a generation request
 */
struct FullPreviewGenerationEvent: Equatable, Sendable, PreviewComparable {
	static let initialState: Self = .init(requestID: -1, state: .initialState)

	static func empty(error: String? = nil, requestID: Int) -> Self{
		.init(requestID: requestID, state: .empty(error: error))
	}

	static func cancelled(requestID: Int) -> Self {
		.init(requestID: requestID, state: .cancelled)
	}
	static func generating(settings: SettingsForFullPreview, progress: Double, requestID: Int) -> Self {
		.init(requestID: requestID, state: .generating(.init(settings: settings, progress: progress)))
	}

	static func ready(settings: SettingsForFullPreview, gifData: [SendableTexture?], requestID: Int) -> Self {
		.init(requestID: requestID, state: .ready(.init(settings: settings, gifData: gifData)))
	}

	let requestID: Int

	var canShowPreview: Bool {
		switch self.state {
		case .empty, .cancelled:
			false
		case .generating, .ready:
			true
		}
	}

	var errorMessage: String? {
		switch self.state {
		case .empty(error: let error):
			error
		case .generating, .ready, .cancelled:
			nil
		}
	}

	var progress: Double {
		switch self.state {
		case .empty, .cancelled:
			0.0
		case let .generating(generating):
			generating.progress
		case .ready:
			1.0
		}
	}

	var isGenerating: Bool {
		switch self.state {
		case .generating:
			true
		case .empty, .ready, .cancelled:
			false
		}
	}

	/**
	 - Returns the texture that represents the current Preview Frame, or nil if there is no preview for this frame
	 */
	func getPreviewFrame(
		originalFrame: CVPixelBuffer,
		compositionTime: CMTime
	) async throws -> SendableTexture? {
		switch self.state {
		case .empty, .cancelled:
			nil
		case let .generating(generating):
			try await originalFrame.convertToGIF(settings: generating.settings).convertToTexture()
		case let .ready( fullPreview):
			try fullPreview.getGIF(at: compositionTime)
		}
	}

	/**
	 See if we can skip generating a fullPreview based on the last state

	 - Returns: `true` if a new generation is required, `false` otherwise.
	 */
	func isNecessaryToCreateNewFullPreview(newSettings: SettingsForFullPreview, newRequestID: Int) -> Bool {
		settings?.areSettingsDifferentEnoughForANewFullPreview(newSettings: newSettings, areCurrentlyGenerating: isGenerating, oldRequestID: requestID, newRequestID: newRequestID) ?? true
	}
	private var settings: SettingsForFullPreview? {
		switch self.state {
		case .empty, .cancelled:
			nil
		case let .generating(generating):
			generating.settings
		case let .ready(fullPreview):
			fullPreview.settings
		}
	}

	private let state: State

	private enum State: Equatable {
		case empty(error: String?)
		case cancelled
		case generating(Generating)
		case ready(FullPreview)
		static let initialState: Self = .empty(error: nil)

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

	private struct FullPreview: Equatable {
		let settings: SettingsForFullPreview
		let gifData: [SendableTexture?]

		func getGIF(at compositionTime: CMTime) throws(GetGIFError) -> SendableTexture {
			guard let image = gifData[getCurrentGIFIndex(at: compositionTime)] else {
				throw GetGIFError.failedToGetGIFFrame
			}
			return image
		}

		enum GetGIFError: Error {
			case failedToGetGIFFrame
		}

		private func getCurrentGIFIndex(at compositionTime: CMTime) -> Int {
			let timeRangeInOriginalSpeed = settings.conversion.timeRange ?? (0...settings.assetDuration)

			let gifTimeInOriginalSpeed = originalCompositionTime(from: compositionTime) - timeRangeInOriginalSpeed.lowerBound
			let adjustedFramesPerSecond = Double(settings.framesPerSecondsWithoutSpeedAdjustment) / settings.speed

			return Int(floor(gifTimeInOriginalSpeed * adjustedFramesPerSecond ))
				.clamped(from: 0, to: gifData.count - 1)
		}

		/**
		 Time that been scaled. The composition will speed up or slowdown the time.   for example if the player is at 2x speed. This struct it takes the reported time of 0.5 and multiplies it by 2, to get 1 second the original  time in the composition.
		 */
		private func originalCompositionTime(from reportedCompositionTime: CMTime) -> Double {
			reportedCompositionTime.seconds * settings.speed
		}


		/**
		 Are equal if the settings that led to the creation of a full preview are equal
		 */
		static func == (lhs: Self, rhs: Self) -> Bool {
			lhs.settings == rhs.settings
		}
	}

	/**
	 PreviewComparable compares if the image on the screen is visually different between the two states.
	 */
	static func ~= (lhs: Self, rhs: Self) -> Bool {
		// If we have two settings, compare if the settings are the same
		if let lhsSettings = lhs.settings {
			if let rhsSettings = rhs.settings {
				return lhs.state.sameCase(as: rhs.state) && lhsSettings == rhsSettings
			}
			return false
		}
		// lhs is `no Preview`, so if rhs has `settings` we know we are different
		if rhs.settings != nil {
			return false
		}
		// lhs has `no preview` and rhs has `no preview`; we are the same
		return true
	}
}
