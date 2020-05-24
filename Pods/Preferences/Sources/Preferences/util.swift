import Cocoa

extension NSImage {
	static var empty: NSImage { NSImage(size: .zero) }
}

extension NSView {
	@discardableResult
	func constrainToSuperviewBounds() -> [NSLayoutConstraint] {
		guard let superview = superview else {
			preconditionFailure("superview has to be set first")
		}

		var result = [NSLayoutConstraint]()
		result.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: "H:|-0-[subview]-0-|", options: .directionLeadingToTrailing, metrics: nil, views: ["subview": self]))
		result.append(contentsOf: NSLayoutConstraint.constraints(withVisualFormat: "V:|-0-[subview]-0-|", options: .directionLeadingToTrailing, metrics: nil, views: ["subview": self]))
		translatesAutoresizingMaskIntoConstraints = false
		superview.addConstraints(result)

		return result
	}
}

extension NSEvent {
	/// Events triggered by user interaction.
	static let userInteractionEvents: [NSEvent.EventType] = {
		var events: [NSEvent.EventType] = [
			.leftMouseDown,
			.leftMouseUp,
			.rightMouseDown,
			.rightMouseUp,
			.leftMouseDragged,
			.rightMouseDragged,
			.keyDown,
			.keyUp,
			.scrollWheel,
			.tabletPoint,
			.otherMouseDown,
			.otherMouseUp,
			.otherMouseDragged,
			.gesture,
			.magnify,
			.swipe,
			.rotate,
			.beginGesture,
			.endGesture,
			.smartMagnify,
			.quickLook,
			.directTouch
		]

		if #available(macOS 10.10.3, *) {
			events.append(.pressure)
		}

		return events
	}()

	/// Whether the event was triggered by user interaction.
	var isUserInteraction: Bool { NSEvent.userInteractionEvents.contains(type) }
}

extension Bundle {
	var appName: String {
		string(forInfoDictionaryKey: "CFBundleDisplayName")
			?? string(forInfoDictionaryKey: "CFBundleName")
			?? string(forInfoDictionaryKey: "CFBundleExecutable")
			?? "<Unknown App Name>"
	}

	private func string(forInfoDictionaryKey key: String) -> String? {
		// `object(forInfoDictionaryKey:)` prefers localized info dictionary over the regular one automatically
		object(forInfoDictionaryKey: key) as? String
	}
}
