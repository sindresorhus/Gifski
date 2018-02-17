//
//  BaseView.swift
//  ProgressKit
//
//  Created by Kauntey Suryawanshi on 04/10/15.
//  Copyright (c) 2015 Kauntey Suryawanshi. All rights reserved.
//

#if os(OSX)
import AppKit

@IBDesignable
open class BaseView : NSView {

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.configureLayers()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        self.configureLayers()
    }

    /// Configure the Layers
    func configureLayers() {
        self.wantsLayer = true
        notifyViewRedesigned()
    }

    @IBInspectable open var background: NSColor = NSColor(red: 88.3 / 256, green: 104.4 / 256, blue: 118.5 / 256, alpha: 1.0) {
        didSet {
            self.notifyViewRedesigned()
        }
    }

    @IBInspectable open var foreground: NSColor = NSColor(red: 66.3 / 256, green: 173.7 / 256, blue: 106.4 / 256, alpha: 1.0) {
        didSet {
            self.notifyViewRedesigned()
        }
    }

    @IBInspectable open var cornerRadius: CGFloat = 5.0 {
        didSet {
            self.notifyViewRedesigned()
        }
    }

    /// Call when any IBInspectable variable is changed
    func notifyViewRedesigned() {
        self.layer?.backgroundColor = background.cgColor
        self.layer?.cornerRadius = cornerRadius
    }
}

#endif



