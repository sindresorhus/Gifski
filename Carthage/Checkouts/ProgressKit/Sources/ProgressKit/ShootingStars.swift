//
//  ShootingStars.swift
//  ProgressKit
//
//  Created by Kauntey Suryawanshi on 09/07/15.
//  Copyright (c) 2015 Kauntey Suryawanshi. All rights reserved.
//

#if os(OSX)

import Foundation
import Cocoa

@IBDesignable
open class ShootingStars: IndeterminateAnimation {
    fileprivate let animationDuration = 1.0

    var starLayer1 = CAShapeLayer()
    var starLayer2 = CAShapeLayer()
    var animation = CABasicAnimation(keyPath: "position.x")
    var tempAnimation = CABasicAnimation(keyPath: "position.x")

    override func notifyViewRedesigned() {
        super.notifyViewRedesigned()
        starLayer1.backgroundColor = foreground.cgColor
        starLayer2.backgroundColor = foreground.cgColor
    }

    override func configureLayers() {
        super.configureLayers()

        let rect = self.bounds
        let dimension = rect.height
        let starWidth = dimension * 1.5
        
        self.layer?.cornerRadius = 0

        /// Add Stars
        do {
            starLayer1.position = CGPoint(x: dimension / 2, y: dimension / 2)
            starLayer1.bounds.size = CGSize(width: starWidth, height: dimension)
            starLayer1.backgroundColor = foreground.cgColor
            self.layer?.addSublayer(starLayer1)
            
            starLayer2.position = CGPoint(x: rect.midX, y: dimension / 2)
            starLayer2.bounds.size = CGSize(width: starWidth, height: dimension)
            starLayer2.backgroundColor = foreground.cgColor
            self.layer?.addSublayer(starLayer2)
        }
        
        /// Add default animation
        do {
            animation.fromValue = -dimension
            animation.toValue = rect.width * 0.9
            animation.duration = animationDuration
            animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
            animation.isRemovedOnCompletion = false
            animation.repeatCount = Float.infinity
        }
        
        /** Temp animation will be removed after first animation
            After finishing it will invoke animationDidStop and starLayer2 is also given default animation.
        The purpose of temp animation is to generate an temporary offset
        */
        tempAnimation.fromValue = rect.midX
        tempAnimation.toValue = rect.width
        tempAnimation.delegate = self
        tempAnimation.duration = animationDuration / 2
        tempAnimation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseIn)
    }

    //MARK: Indeterminable protocol
    override func startAnimation() {
        starLayer1.add(animation, forKey: "default")
        starLayer2.add(tempAnimation, forKey: "tempAnimation")
    }
    
    override func stopAnimation() {
        starLayer1.removeAllAnimations()
        starLayer2.removeAllAnimations()
    }
}

extension ShootingStars: CAAnimationDelegate {
    open func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        starLayer2.add(animation, forKey: "default")
    }
}

#endif
