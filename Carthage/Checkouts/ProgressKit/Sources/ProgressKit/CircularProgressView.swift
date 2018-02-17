//
//  CircularView.swift
//  Animo
//
//  Created by Kauntey Suryawanshi on 29/06/15.
//  Copyright (c) 2015 Kauntey Suryawanshi. All rights reserved.
//

import Foundation

#if os(OSX)

import Cocoa

@IBDesignable
open class CircularProgressView: DeterminateAnimation {

    open var backgroundCircle = CAShapeLayer()
    open var progressLayer = CAShapeLayer()
    open var percentLabelLayer = CATextLayer()

    @IBInspectable open var strokeWidth: CGFloat = -1 {
        didSet {
            notifyViewRedesigned()
        }
    }
    
    @IBInspectable open var showPercent: Bool = true {
        didSet {
            notifyViewRedesigned()
        }
    }

    override func notifyViewRedesigned() {
        super.notifyViewRedesigned()
        backgroundCircle.lineWidth = self.strokeWidth / 2
        progressLayer.lineWidth = strokeWidth
        percentLabelLayer.isHidden = !showPercent

        backgroundCircle.strokeColor = foreground.withAlphaComponent(0.5).cgColor
        progressLayer.strokeColor = foreground.cgColor
        percentLabelLayer.foregroundColor = foreground.cgColor
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
        progressLayer.strokeEnd = max(0, min(progress, 1))
        percentLabelLayer.string = "\(Int(progress * 100))%"
        CATransaction.commit()
    }

    override func configureLayers() {
        super.configureLayers()
        let rect = self.bounds
        let radius = (rect.width / 2) * 0.75
        let strokeScalingFactor = CGFloat(0.05)
        

        // Add background Circle
        do {
            backgroundCircle.frame = rect
            backgroundCircle.lineWidth = strokeWidth == -1 ? (rect.width * strokeScalingFactor / 2) : strokeWidth / 2
            
            backgroundCircle.strokeColor = foreground.withAlphaComponent(0.5).cgColor
            backgroundCircle.fillColor = NSColor.clear.cgColor
            let backgroundPath = NSBezierPath()
            backgroundPath.appendArc(withCenter: rect.mid, radius: radius, startAngle: 0, endAngle: 360)
            backgroundCircle.path = backgroundPath.CGPath
            self.layer?.addSublayer(backgroundCircle)
        }
        
        // Progress Layer
        do {
            progressLayer.strokeEnd = 0 //REMOVe this
            progressLayer.fillColor = NSColor.clear.cgColor
            progressLayer.lineCap = kCALineCapRound
            progressLayer.lineWidth = strokeWidth == -1 ? (rect.width * strokeScalingFactor) : strokeWidth
            
            progressLayer.frame = rect
            progressLayer.strokeColor = foreground.cgColor
            let arcPath = NSBezierPath()
            let startAngle = CGFloat(90)
            arcPath.appendArc(withCenter: rect.mid, radius: radius, startAngle: startAngle, endAngle: (startAngle - 360), clockwise: true)
            progressLayer.path = arcPath.CGPath
            self.layer?.addSublayer(progressLayer)
        }

        // Percentage Layer
        do {
            percentLabelLayer.string = "0%"
            percentLabelLayer.foregroundColor = foreground.cgColor
            percentLabelLayer.frame = rect
            percentLabelLayer.font = "Helvetica Neue Light" as CFTypeRef
            percentLabelLayer.alignmentMode = kCAAlignmentCenter
            percentLabelLayer.position.y = rect.midY * 0.25
            percentLabelLayer.fontSize = rect.width * 0.2
            self.layer?.addSublayer(percentLabelLayer)
        }
    }
}

#endif
