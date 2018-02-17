//
//  DeterminateAnimation.swift
//  ProgressKit
//
//  Created by Kauntey Suryawanshi on 09/07/15.
//  Copyright (c) 2015 Kauntey Suryawanshi. All rights reserved.
//
#if os(OSX)

import Foundation
import Cocoa

protocol DeterminableAnimation {
    func updateProgress()
}

@IBDesignable
open class DeterminateAnimation: BaseView, DeterminableAnimation {
    
    @IBInspectable open var animated: Bool = true

    /// Value of progress now. Range 0..1
    @IBInspectable open var progress: CGFloat = 0 {
        didSet {
            updateProgress()
        }
    }

    /// This function will only be called by didSet of progress. Every subclass will have its own implementation
    func updateProgress() {
        fatalError("Must be overriden in subclass")
    }
}
    
#endif
