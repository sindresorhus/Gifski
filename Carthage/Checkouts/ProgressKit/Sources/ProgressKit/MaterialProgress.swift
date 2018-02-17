//
//  MaterialProgress.swift
//  ProgressKit
//
//  Created by Kauntey Suryawanshi on 30/06/15.
//  Copyright (c) 2015 Kauntey Suryawanshi. All rights reserved.
//
#if os(OSX)
    
import Foundation
import Cocoa

private let duration = 1.5
private let strokeRange = (start: 0.0, end: 0.8)

@IBDesignable
open class MaterialProgress: IndeterminateAnimation {

    @IBInspectable open var lineWidth: CGFloat = -1 {
        didSet {
            progressLayer.lineWidth = lineWidth
        }
    }

    override func notifyViewRedesigned() {
        super.notifyViewRedesigned()
        progressLayer.strokeColor = foreground.cgColor
    }

    var backgroundRotationLayer = CAShapeLayer()

    var progressLayer: CAShapeLayer = {
        var tempLayer = CAShapeLayer()
        tempLayer.strokeEnd = CGFloat(strokeRange.end)
        tempLayer.lineCap = kCALineCapRound
        tempLayer.fillColor = NSColor.clear.cgColor
        return tempLayer
    }()

    //MARK: Animation Declaration
    var animationGroup: CAAnimationGroup = {
        var tempGroup = CAAnimationGroup()
        tempGroup.repeatCount = 1
        tempGroup.duration = duration
        return tempGroup
    }()
    

    var rotationAnimation: CABasicAnimation = {
        var tempRotation = CABasicAnimation(keyPath: "transform.rotation")
        tempRotation.repeatCount = Float.infinity
        tempRotation.fromValue = 0
        tempRotation.toValue = 1
        tempRotation.isCumulative = true
        tempRotation.duration = duration / 2
        return tempRotation
        }()

    /// Makes animation for Stroke Start and Stroke End
    func makeStrokeAnimationGroup() {
        var strokeStartAnimation: CABasicAnimation!
        var strokeEndAnimation: CABasicAnimation!

        func makeAnimationforKeyPath(_ keyPath: String) -> CABasicAnimation {
            let tempAnimation = CABasicAnimation(keyPath: keyPath)
            tempAnimation.repeatCount = 1
            tempAnimation.speed = 2.0
            tempAnimation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)

            tempAnimation.fromValue = strokeRange.start
            tempAnimation.toValue =  strokeRange.end
            tempAnimation.duration = duration

            return tempAnimation
        }
        strokeEndAnimation = makeAnimationforKeyPath("strokeEnd")
        strokeStartAnimation = makeAnimationforKeyPath("strokeStart")
        strokeStartAnimation.beginTime = duration / 2
        animationGroup.animations = [strokeEndAnimation, strokeStartAnimation, ]
        animationGroup.delegate = self
    }

    override func configureLayers() {
        super.configureLayers()
        makeStrokeAnimationGroup()
        let rect = self.bounds

        backgroundRotationLayer.frame = rect
        self.layer?.addSublayer(backgroundRotationLayer)

        // Progress Layer
        let radius = (rect.width / 2) * 0.75
        progressLayer.frame =  rect
        progressLayer.lineWidth = lineWidth == -1 ? radius / 10: lineWidth
        let arcPath = NSBezierPath()
        arcPath.appendArc(withCenter: rect.mid, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        progressLayer.path = arcPath.CGPath
        backgroundRotationLayer.addSublayer(progressLayer)
    }

    var currentRotation = 0.0
    let π2 = Double.pi * 2

    override func startAnimation() {
        progressLayer.add(animationGroup, forKey: "strokeEnd")
        backgroundRotationLayer.add(rotationAnimation, forKey: rotationAnimation.keyPath)
    }
    override func stopAnimation() {
        backgroundRotationLayer.removeAllAnimations()
        progressLayer.removeAllAnimations()
    }
}

extension MaterialProgress: CAAnimationDelegate {
    open func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if !animate { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentRotation += strokeRange.end * π2
        currentRotation = currentRotation.truncatingRemainder(dividingBy: π2)
        progressLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat( currentRotation)))
        CATransaction.commit()
        progressLayer.add(animationGroup, forKey: "strokeEnd")
    }
}
#endif
