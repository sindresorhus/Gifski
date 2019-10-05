//
//  CheckerboardView.swift
//  Gifski
//
//  Created by Sergey Kuryanov on 06/10/2019.
//  Copyright © 2019 Sindre Sorhus. All rights reserved.
//

import Cocoa

class CheckerboardView: NSView {
	let gridSize = CGSize(width: 10, height: 10)
	let firstColor = NSColor.white
	let secondColor = NSColor.lightGray

	let clearRect: CGRect

	init(frame: NSRect, clearRect: CGRect) {
		self.clearRect = clearRect

		super.init(frame: frame)
	}

	required init?(coder: NSCoder) {
		self.clearRect = .zero

		super.init(coder: coder)
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)

		firstColor.setFill()
		dirtyRect.fill()

		secondColor.setFill()

		for y in 0...Int(bounds.size.height / gridSize.height) {
			for x in 0...Int(bounds.size.width / gridSize.width) where x % 2 == y % 2 {
				let origin = CGPoint(x: x * Int(gridSize.width), y: y * Int(gridSize.height))
				let rect = CGRect(origin: origin, size: gridSize)
				rect.fill()
			}
		}

		clearRect.fill(using: .clear)
	}
}
