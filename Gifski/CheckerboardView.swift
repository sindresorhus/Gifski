//
//  CheckerboardView.swift
//  Gifski
//
//  Created by Sergey Kuryanov on 06/10/2019.
//  Copyright © 2019 Sindre Sorhus. All rights reserved.
//

import Cocoa

final class CheckerboardView: NSView {
	private let gridSize = CGSize(width: 10, height: 10)
	private let firstColor = NSColor.white
	private let secondColor = NSColor.lightGray
	private let clearRect: CGRect

	init(frame: CGRect, clearRect: CGRect) {
		self.clearRect = clearRect

		super.init(frame: frame)
	}

	required init?(coder: NSCoder) {
		self.clearRect = .zero

		super.init(coder: coder)
	}

	override func draw(_ dirtyRect: CGRect) {
		super.draw(dirtyRect)

		firstColor.setFill()
		dirtyRect.fill()

		secondColor.setFill()

		for y in 0...Int(bounds.size.height / gridSize.height) {
			for x in 0...Int(bounds.size.width / gridSize.width) where x.isEven == y.isEven {
				let origin = CGPoint(x: x * Int(gridSize.width), y: y * Int(gridSize.height))
				let rect = CGRect(origin: origin, size: gridSize)
				rect.fill()
			}
		}

		clearRect.fill(using: .clear)
	}
}
