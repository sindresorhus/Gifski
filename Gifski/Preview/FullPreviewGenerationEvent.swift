//
//  FullPreviewGenerationEvent.swift
//  Gifski
//
//  Created by Michael Mulet on 4/24/25.
//

import Foundation
import AVFoundation
import Metal

/**
 Events that will be emitted by the PreviewStream, they represent the state or a generation request
 */
enum FullPreviewGenerationEvent {
	case empty(error: String?, requestID: Int)
	case generating(settings: SettingsForFullPreview, progress: Double, requestID: Int)
	case ready(settings: SettingsForFullPreview, asset: AVAsset, preBaked: PreBakedFrames, requestID: Int)
	static let initialState: Self = .empty(error: nil, requestID: -1)
	var requestID: Int {
		switch self {
		case	.empty(_, requestID: let requestID),
				.generating(_, _, requestID: let requestID),
				.ready(_, _, _, requestID: let requestID):
			return requestID
		}
	}
	var progress: Double{
		switch self {
		case .empty:
			return 0.0
		case .generating(_, progress: let progress, _):
			return progress
		case .ready:
			return 1.0
		}
	}
	var isGenerating: Bool {
		switch self {
		case .generating:
			return true
		case .empty, .ready:
			return false
		}
	}
	var status: Status? {
		switch self {
		case .empty:
			return nil
		case .generating(settings: let settings, _, _):
			return .init(settings: settings, preBaked: nil, ready: false)
		case .ready(settings: let settings, _, let preBaked, _):
			return .init(settings: settings, preBaked: preBaked, ready: true)
		}
	}
	/**
	 The Sendable subset of the generation
	 */
	struct Status: Equatable {
		static func == (lhs: FullPreviewGenerationEvent.Status, rhs: FullPreviewGenerationEvent.Status) -> Bool {
			lhs.settings == rhs.settings && lhs.ready == rhs.ready
		}

		let settings: SettingsForFullPreview
		let preBaked: PreBakedFrames?
		let ready: Bool
	}
}

extension Optional where Wrapped == FullPreviewGenerationEvent.Status {
	var isGenerating: Bool {
		switch self {
		case .none:
			return false
		case .some(let status):
			return !status.ready
		}
	}
}
