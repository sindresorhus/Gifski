import SwiftUI

struct StartScreen: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		VStack(spacing: 8) {
			Text("Drop Video")
			Text("or")
				.font(.system(size: 10))
				.italic()
			Button("Open") {
				appState.isFileImporterPresented = true
			}
		}
		.font(.title3)
		.controlSize(.extraLarge)
		.foregroundStyle(.secondary)
		.padding()
		.fillFrame()
		.navigationTitle("")
		// TODO: When targeting macOS 15, set `.containerShape()` at the top-level and then use `ContainerRelativeShape()` for the border.
		// TODO: Or do a `.windowBorder()` utility.
	}
}
