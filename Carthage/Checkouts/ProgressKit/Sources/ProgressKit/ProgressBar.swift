//
//  ProgressBar.swift
//  ProgressKit
//
//  Created by Kauntey Suryawanshi on 31/07/15.
//  Copyright (c) 2015 Kauntey Suryawanshi. All rights reserved.
//
#if os(OSX)
    
import Foundation
import Cocoa

@IBDesignable
open class ProgressBar: DeterminateAnimation {

    open var borderLayer = CAShapeLayer()
    open var progressLayer = CAShapeLayer()
    
    @IBInspectable open var borderColor: NSColor = NSColor.black {
        didSet {
            notifyViewRedesigned()
        }
    }

    override func notifyViewRedesigned() {
        super.notifyViewRedesigned()
        self.layer?.cornerRadius = self.frame.height / 2
        borderLayer.borderColor = borderColor.cgColor
        progressLayer.backgroundColor = foreground.cgColor
    }

    override func configureLayers() {
        super.configureLayers()

        borderLayer.frame = self.bounds
        borderLayer.cornerRadius = borderLayer.frame.height / 2
        borderLayer.borderWidth = 1.0
        self.layer?.addSublayer(borderLayer)

        progressLayer.frame = NSInsetRect(borderLayer.bounds, 3, 3)
        progressLayer.frame.size.width = (borderLayer.bounds.width - 6)
        progressLayer.cornerRadius = progressLayer.frame.height / 2
        progressLayer.backgroundColor = foreground.cgColor
        borderLayer.addSublayer(progressLayer)

    }
    
    override func updateProgress() {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.5)
        } else {
            CATransaction.setDisableActions(true)
        }
        let timing = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
        CATransaction.setAnimationTimingFunction(timing)
        progressLayer.frame.size.width = (borderLayer.bounds.width - 6) * progress
        CATransaction.commit()
    }
}
#endif
