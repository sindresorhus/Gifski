//: Playground - noun: a place where people can play

import Cocoa
import ProgressKit
import PlaygroundSupport

/**
 This playground has examples of how to use the UI components.
 Enable the assistant editor in Xcode and uncomment
 the PlaygroundPage.current.liveView code path for each
 component to see it in action.
 
 Modify to test behavior, change colors etc.
 */

PlaygroundPage.current.needsIndefiniteExecution = true

let circularProgress : CircularProgressView = {
    let _circularProgressView = CircularProgressView(frame: NSRect(x: 0, y: 0, width: 144, height: 144))
    _circularProgressView.progressLayer.borderWidth = 10
    _circularProgressView.progress = 0.5 //half way
    return _circularProgressView
}()
//PlaygroundPage.current.liveView = circularProgress

let crawler : Crawler = {
    //Crawler
    let _crawler = Crawler(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
    _crawler.startAnimation()
    return _crawler
}()
//PlaygroundPage.current.liveView = crawler

let materialProgress : MaterialProgress = {
    //Material Progress
    let _materialProgress = MaterialProgress(frame: NSRect(x: 0, y: 0, width: 144, height: 144))
    _materialProgress.animate = true
    return _materialProgress
}()
//PlaygroundPage.current.liveView = materialProgress

let progressBar : ProgressBar = {
    //Progress Bar
    let _progressBar = ProgressBar(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
    _progressBar.progress = 0.5
    return _progressBar
}()
//PlaygroundPage.current.liveView = progressBar

let rainbow : Rainbow = {
    //Rainbow Progress
    let _rainbow = Rainbow(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    _rainbow.animate = true
    return _rainbow
}()
//PlaygroundPage.current.liveView = rainbow

let shootingStars : ShootingStars = {
    //Rotating Arc
    let _shootingStars = ShootingStars(frame: NSRect(x: 0, y: 0, width: 460, height: 10))
    _shootingStars.animate = true
    return _shootingStars
}()
//PlaygroundPage.current.liveView = shootingStars

let spinner : Spinner = {
    //Spinner
    let _spinner = Spinner(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    _spinner.animate = true
    return _spinner
}()

//PlaygroundPage.current.liveView = spinner



