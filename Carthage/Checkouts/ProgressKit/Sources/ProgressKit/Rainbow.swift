//
//  Rainbow.swift
//  ProgressKit
//
//  Created by Kauntey Suryawanshi on 09/07/15.
//  Copyright (c) 2015 Kauntey Suryawanshi. All rights reserved.
//

#if os(OSX)

import Foundation
import Cocoa

@IBDesignable
open class Rainbow: MaterialProgress {

    @IBInspectable open var onLightOffDark: Bool = false

    override func configureLayers() {
        super.configureLayers()
        self.background = NSColor.clear
    }

    override open func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        super.animationDidStop(anim, finished: flag)
        if onLightOffDark {
            progressLayer.strokeColor = lightColorList[Int(arc4random()) % lightColorList.count].cgColor
        } else {
            progressLayer.strokeColor = darkColorList[Int(arc4random()) % darkColorList.count].cgColor
        }
    }
}

var randomColor: NSColor {
    let red   = CGFloat(Double(arc4random()).truncatingRemainder(dividingBy: 256.0) / 256.0)
    let green = CGFloat(Double(arc4random()).truncatingRemainder(dividingBy: 256.0) / 256.0)
    let blue  = CGFloat(Double(arc4random()).truncatingRemainder(dividingBy: 256.0) / 256.0)
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
}

private let lightColorList:[NSColor] = [
    NSColor(red: 0.9461, green: 0.6699, blue: 0.6243, alpha: 1.0),
    NSColor(red: 0.8625, green: 0.7766, blue: 0.8767, alpha: 1.0),
    NSColor(red: 0.6676, green: 0.6871, blue: 0.8313, alpha: 1.0),
    NSColor(red: 0.7263, green: 0.6189, blue: 0.8379, alpha: 1.0),
    NSColor(red: 0.8912, green: 0.9505, blue: 0.9971, alpha: 1.0),
    NSColor(red: 0.7697, green: 0.9356, blue: 0.9692, alpha: 1.0),
    NSColor(red: 0.3859, green: 0.7533, blue: 0.9477, alpha: 1.0),
    NSColor(red: 0.6435, green: 0.8554, blue: 0.8145, alpha: 1.0),
    NSColor(red: 0.8002, green: 0.936,  blue: 0.7639, alpha: 1.0),
    NSColor(red: 0.5362, green: 0.8703, blue: 0.8345, alpha: 1.0),
    NSColor(red: 0.9785, green: 0.8055, blue: 0.4049, alpha: 1.0),
    NSColor(red: 1.0,    green: 0.8667, blue: 0.6453, alpha: 1.0),
    NSColor(red: 0.9681, green: 0.677,  blue: 0.2837, alpha: 1.0),
    NSColor(red: 0.9898, green: 0.7132, blue: 0.1746, alpha: 1.0),
    NSColor(red: 0.8238, green: 0.84,   blue: 0.8276, alpha: 1.0),
    NSColor(red: 0.8532, green: 0.8763, blue: 0.883,  alpha: 1.0),
]

let darkColorList: [NSColor] = [
    NSColor(red: 0.9472, green: 0.2496, blue: 0.0488, alpha: 1.0),
    NSColor(red: 0.8098, green: 0.1695, blue: 0.0467, alpha: 1.0),
    NSColor(red: 0.853,  green: 0.2302, blue: 0.3607, alpha: 1.0),
    NSColor(red: 0.8152, green: 0.3868, blue: 0.5021, alpha: 1.0),
    NSColor(red: 0.96,   green: 0.277,  blue: 0.3515, alpha: 1.0),
    NSColor(red: 0.3686, green: 0.3069, blue: 0.6077, alpha: 1.0),
    NSColor(red: 0.5529, green: 0.3198, blue: 0.5409, alpha: 1.0),
    NSColor(red: 0.2132, green: 0.4714, blue: 0.7104, alpha: 1.0),
    NSColor(red: 0.1706, green: 0.2432, blue: 0.3106, alpha: 1.0),
    NSColor(red: 0.195,  green: 0.2982, blue: 0.3709, alpha: 1.0),
    NSColor(red: 0.0,    green: 0.3091, blue: 0.5859, alpha: 1.0),
    NSColor(red: 0.2261, green: 0.6065, blue: 0.3403, alpha: 1.0),
    NSColor(red: 0.1101, green: 0.5694, blue: 0.4522, alpha: 1.0),
    NSColor(red: 0.1716, green: 0.4786, blue: 0.2877, alpha: 1.0),
    NSColor(red: 0.8289, green: 0.33,   blue: 0.0,    alpha: 1.0),
    NSColor(red: 0.4183, green: 0.4842, blue: 0.5372, alpha: 1.0),
    NSColor(red: 0.0,    green: 0.0,    blue: 0.0,    alpha: 1.0),
]
#endif
