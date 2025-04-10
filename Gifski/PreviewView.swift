//
//  PreviewView.swift
//  Gifski
//
//  Created by Michael Mulet on 3/21/25.
//

import SwiftUI

@MainActor
final class PreviewViewState: ObservableObject {
	@Published var previewImage: NSImage?
	init(previewImage: NSImage? = nil) {
		self.previewImage = previewImage
	}
}

struct PreviewView: View {
	@ObservedObject var previewViewState: PreviewViewState // swiftlint:disable:this swiftui_state_private
    var body: some View {
		ZStack {
			CheckerboardView()
			VStack {
				ImageView(image: previewViewState.previewImage ?? NSImage())
					.scaledToFit()
				Text("Preview")
			}
		}
	}
}
