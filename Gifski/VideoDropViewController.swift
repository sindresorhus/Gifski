import SwiftUI

struct DropCenterView: View {
	var body: some View {
		VStack {
			Text("Drop a Video")
			Text("or")
				.font(.system(size: 10))
				.italic()
				.padding(.top, 6)
			Button("Open") {
				AppDelegate.shared.mainWindowController.presentOpenPanel()
			}
		}
			.foregroundColor(.secondary)
	}
}

final class VideoDropViewController: NSViewController {
	private let videoValidator = VideoValidator()

	private lazy var videoDropView = with(VideoDropView()) {
		$0.dropView = NSHostingView(rootView: DropCenterView())

		$0.onComplete = { [weak self] url in
			NSApp.activate(ignoringOtherApps: true)

			// This is a workaround so the dropped thumbnail doesn't get visually stuck while a modal dialog is presented.
			DispatchQueue.main.async {
				self?.convert(url)
			}
		}
	}

	convenience init(dropLabelIsHidden: Bool = false) {
		self.init()

		videoDropView.isDropLabelHidden = dropLabelIsHidden
	}

	override func loadView() {
		let view = videoDropView
		view.frame.size = Constants.defaultWindowSize
		self.view = view
	}

	func convert(_ inputUrl: URL) {
		guard
			case .success(let asset, let videoMetadata) = videoValidator.validate(inputUrl, in: view.window)
		else {
			return
		}

		let editController = EditVideoViewController(inputUrl: inputUrl, asset: asset, videoMetadata: videoMetadata)
		push(viewController: editController)
	}
}
