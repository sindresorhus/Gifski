import Cocoa
import Fabric
import Crashlytics

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	lazy var mainWindowController = MainWindowController()
	var hasFinishedLaunching = false
	var urlToConvertOnLaunch: URL!

	func applicationWillFinishLaunching(_ notification: Notification) {
		UserDefaults.standard.register(defaults: [
			"NSApplicationCrashOnExceptions": true,
			"NSFullScreenMenuItemEverywhere": false
		])
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		#if !DEBUG
			Fabric.with([Crashlytics.self])
		#endif

		mainWindowController.showWindow(self)

		hasFinishedLaunching = true
		NSApp.isAutomaticCustomizeTouchBarMenuItemEnabled = true
		NSApp.servicesProvider = self

		if urlToConvertOnLaunch != nil {
			mainWindowController.convert(urlToConvertOnLaunch)
		}

		mainWindowController.window?.printResponderChainOnChanges()
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		guard urls.count == 1, let videoUrl = urls.first else {
			NSAlert.showModal(
				for: mainWindowController.window,
				message: "Gifski can only convert a single file at the time."
			)
			return
		}

		// TODO: Simplify this. Make a function that calls the input when the app finished launching, or right away if it already has.
		if hasFinishedLaunching {
			mainWindowController.convert(videoUrl)
		} else {
			// This method is called before `applicationDidFinishLaunching`,
			// so we buffer it up a video is "Open with" this app
			urlToConvertOnLaunch = videoUrl
		}
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return true
	}

	func application(_ application: NSApplication, willPresentError error: Error) -> Error {
		Crashlytics.recordNonFatalError(error: error)
		return error
	}
}

extension NSResponder {
	/// Get the responder chain as a sequence.
	var nextResponderChain: AnySequence<NSResponder> {
		var currentNextResponder = nextResponder

		return AnySequence(AnyIterator<NSResponder> {
			defer {
				currentNextResponder = currentNextResponder?.nextResponder
			}

			return currentNextResponder
		})
	}
}

extension NSWindow {
	func printResponderChain() {
		print("Responder chain:")

		print("(Main view controller: \(contentViewController)")

		guard let firstResponder = self.firstResponder else {
			print("  - None")
			return
		}

		print("  - \(firstResponder)")

		for responder in firstResponder.nextResponderChain {
			print("  - \(responder)")
		}
	}

	func printResponderChainOnChanges() {
		printResponderChain()

		observe(\.firstResponder) { window, _  in
			window.printResponderChain()
		}.tiedToLifetimeOf(self)
	}

	// TODO: Write a similar thing for `NSApplication` that fllows windows by observing `keyWindow`.
}



enum AssociationPolicy {
	case assign
	case retainNonatomic
	case copyNonatomic
	case retain
	case copy

	fileprivate var rawValue: objc_AssociationPolicy {
		switch self {
		case .assign:
			return .OBJC_ASSOCIATION_ASSIGN
		case .retainNonatomic:
			return .OBJC_ASSOCIATION_RETAIN_NONATOMIC
		case .copyNonatomic:
			return .OBJC_ASSOCIATION_COPY_NONATOMIC
		case .retain:
			return .OBJC_ASSOCIATION_RETAIN
		case .copy:
			return .OBJC_ASSOCIATION_COPY
		}
	}
}

final class ObjectAssociation<T: Any> {
	private let policy: AssociationPolicy

	init(policy: AssociationPolicy = .retainNonatomic) {
		self.policy = policy
	}

	subscript(index: Any) -> T? {
		get {
			return objc_getAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque()) as! T?
		} set {
			objc_setAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque(), newValue, policy.rawValue)
		}
	}
}

private let bindLifetimeAssociatedObjectKey = ObjectAssociation<[AnyObject]>()

// TODO: This needs to hold `target` weakly. Right now it introduces a memory leak, as `of` will also keep `target` alive.
/// Binds the lifetime of object A to object B, so when B deallocates, so does A, but not before.
func bindLifetime(of object: AnyObject, to target: AnyObject) {
	var retainedObjects = bindLifetimeAssociatedObjectKey[target] ?? []
	retainedObjects.append(object)
	bindLifetimeAssociatedObjectKey[target] = retainedObjects
}

extension NSKeyValueObservation {
	// Note to self: I like this pattern of composability.
	/// Keeps the observation alive as long as the given object.
	@discardableResult
	func tiedToLifetimeOf(_ object: AnyObject) -> NSKeyValueObservation {
		bindLifetime(of: self, to: object)
		return self
	}
}

extension AppDelegate {
	/// This is called from NSApp as a service resolver
	@objc
	func convertToGif(_ pasteboard: NSPasteboard, userData: String, error: NSErrorPointer) {
		guard let url = pasteboard.fileURLs().first else {
			return
		}

		mainWindowController.convert(url)
	}
}
