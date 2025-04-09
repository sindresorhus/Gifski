import SwiftUI
import AVFoundation

struct EditScreen: View {
	@Environment(AppState.self) private var appState
	@Default(.outputQuality) private var outputQuality
	@Default(.bounceGIF) private var bounceGIF
	@Default(.outputFPS) private var frameRate
	@Default(.loopGIF) private var loopGIF
	@Default(.outputSpeed) private var outputSpeed
	@Default(.suppressKeyframeWarning) private var suppressKeyframeWarning
	@State private var url: URL
	@State private var asset: AVAsset
	@State private var modifiedAsset: AVAsset
	@State private var metadata: AVAsset.VideoMetadata
	@State private var estimatedFileSizeModel = EstimatedFileSizeModel()
	@State private var timeRange: ClosedRange<Double>?
	@State private var loopCount = 0
	@State private var isKeyframeRateChecked = false
	@State private var isReversePlaybackWarningPresented = false
	@State private var resizableDimensions = Dimensions.percent(1, originalSize: .init(widthHeight: 100))
	@State private var shouldShow = false

	init(
		url: URL,
		asset: AVAsset,
		metadata: AVAsset.VideoMetadata
	) {
		self._url = .init(wrappedValue: url)
		self._asset = .init(wrappedValue: asset)
		self._modifiedAsset = .init(wrappedValue: asset)
		self._metadata = .init(wrappedValue: metadata)
	}

	var body: some View {
		VStack {
			// TODO: Move the trimmer outside the video view.
			TrimmingAVPlayer(
				asset: modifiedAsset,
				loopPlayback: loopGIF,
				bouncePlayback: bounceGIF
			) { timeRange in
				DispatchQueue.main.async {
					self.timeRange = timeRange
				}
			}
			EditControls(
				canEditDimensions: true,
				metadata: metadata,
				resizableDimensions: $resizableDimensions,
				loopCount: $loopCount,
				outputFPS: $frameRate,
				outputSpeed: $outputSpeed,
				outputQuality: $outputQuality,
				loopGIF: $loopGIF,
				bounceGIF: $bounceGIF,
				outputResize: .constant(1.0)
			)
			bottomBar
		}
		.background(.ultraThickMaterial)
		.navigationTitle(url.lastPathComponent)
		.navigationDocument(url)
		.onReceive(Defaults.publisher(.outputSpeed, options: []).removeDuplicates().debounce(for: .seconds(0.4), scheduler: DispatchQueue.main)) { _ in
			Task {
				await setSpeed()
			}
		}
		// We cannot use `Defaults.publisher(.outputSpeed, options: [])` without the `options` as it causes some weird glitches.
		.task {
			await setSpeed()
		}
		.onChange(of: outputQuality, initial: true) {
			estimatedFileSizeModel.duration = metadata.duration
			estimatedFileSizeModel.updateEstimate()
		}
		// TODO: Make these a single call when tuples are equatable.
		.onChange(of: resizableDimensions) {
			estimatedFileSizeModel.updateEstimate()
		}
		.onChange(of: timeRange) {
			estimatedFileSizeModel.updateEstimate()
		}
		.onChange(of: bounceGIF) {
			estimatedFileSizeModel.updateEstimate()
		}
		.onChange(of: frameRate) {
			estimatedFileSizeModel.updateEstimate()
		}
		.onChange(of: bounceGIF) {
			guard bounceGIF else {
				return
			}

			showKeyframeRateWarningIfNeeded()
		}
		.alert2(
			"Reverse Playback Preview Limitation",
			message: "Reverse playback may stutter when the video has a low keyframe rate. The GIF will not have the same stutter.",
			isPresented: $isReversePlaybackWarningPresented
		)
		.dialogSuppressionToggle(isSuppressed: $suppressKeyframeWarning)
		.opacity(shouldShow ? 1 : 0)
		.onAppear {
			setUp()
		}
		.task {
			try? await Task.sleep(for: .seconds(0.3))

			withAnimation {
				shouldShow = true
			}
		}
	}

	private func setSpeed() async {
		do {
			// We could have set the `rate` of the player instead of modifying the asset, but it's just easier to modify the asset as then it matches what we want to generate. Otherwise, we would have to translate trimming ranges to the correct speed, etc.
			modifiedAsset = try await asset.firstVideoTrack?.extractToNewAssetAndChangeSpeed(to: Defaults[.outputSpeed]) ?? modifiedAsset
			estimatedFileSizeModel.updateEstimate()
		} catch {
			appState.error = error
		}
	}

	private func setUp() {
		estimatedFileSizeModel.getConversionSettings = { conversionSettings }
	}


	private var bottomBar: some View {
		HStack {
			Spacer()
			Button("Convert") {
				appState.navigationPath.append(.conversion(conversionSettings))
			}
			.keyboardShortcut(.defaultAction)
			.padding(.top, -1) // Makes the bar have equal spacing on top and bottom.
		}
		.overlay {
			EstimatedFileSizeView(model: estimatedFileSizeModel)
		}
		.padding()
		.padding(.top, -16)
	}

	private var conversionSettings: GIFGenerator.Conversion {
		print("resizableDimensions:", resizableDimensions.pixels, resizableDimensions.percent)
		return .init(
			asset: modifiedAsset,
			sourceURL: url,
			timeRange: timeRange,
			quality: outputQuality,
			dimensions: resizableDimensions.pixels.toInt,
			frameRate: frameRate,
			loop: {
				guard loopGIF else {
					return loopCount == 0 ? .never : .count(loopCount)
				}

				return .forever
			}(),
			bounce: bounceGIF
		)
	}

	private func showKeyframeRateWarningIfNeeded(maximumKeyframeInterval: Double = 30) {
		guard
			!isKeyframeRateChecked,
			!Defaults[.suppressKeyframeWarning]
		else {
			return
		}

		isKeyframeRateChecked = true

		Task.detached(priority: .utility) {
			do {
				guard
					let keyframeInfo = try await modifiedAsset.firstVideoTrack?.getKeyframeInfo(),
					keyframeInfo.keyframeInterval > maximumKeyframeInterval
				else {
					return
				}

				print("Low keyframe interval \(keyframeInfo.keyframeInterval)")

				await MainActor.run {
					isReversePlaybackWarningPresented = true
				}
			} catch {
				await MainActor.run {
					appState.error = error
				}
			}
		}
	}
}
