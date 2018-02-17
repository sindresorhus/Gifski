//
//  ProgressUtils.swift
//  ProgressKit
//
//  Created by Kauntey Suryawanshi on 09/07/15.
//  Copyright (c) 2015 Kauntey Suryawanshi. All rights reserved.
//

#if os(OSX)
    
import AppKit

public extension NSRect {
    var mid: CGPoint {
        return CGPoint(x: self.midX, y: self.midY)
    }
}

public extension NSBezierPath {
    /// Converts NSBezierPath to CGPath
    var CGPath: CGPath {
        let path = CGMutablePath()
        let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        let numElements = self.elementCount

        for index in 0..<numElements {
            let pathType = self.element(at: index, associatedPoints: points)
            switch pathType {
            case .moveToBezierPathElement:
                path.move(to: points[0])
            case .lineToBezierPathElement:
                path.addLine(to: points[0])
            case .curveToBezierPathElement:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePathBezierPathElement:
                path.closeSubpath()
            }
        }

        points.deallocate(capacity: 3)
        return path
    }
}

public func degreeToRadian(_ degree: Int) -> Double {
    return Double(degree) * (Double.pi / 180)
}

public func radianToDegree(_ radian: Double) -> Int {
    return Int(radian * (180 / Double.pi))
}

public func + (p1: CGPoint, p2: CGPoint) -> CGPoint {
    return CGPoint(x: p1.x + p2.x, y: p1.y + p2.y)
}
#endif

