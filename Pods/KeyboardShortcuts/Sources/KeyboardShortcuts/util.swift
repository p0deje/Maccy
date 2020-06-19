import Cocoa
import Carbon.HIToolbox


extension Data {
	var string: String? { String(data: self, encoding: .utf8) }
}


extension NSEvent {
	var isKeyEvent: Bool { type == .keyDown || type == .keyUp }
}


extension NSTextField {
	func hideCaret() {
		(currentEditor() as? NSTextView)?.insertionPointColor = .clear
	}
}


extension NSView {
	func focus() {
		window?.makeFirstResponder(self)
	}

	func blur() {
		window?.makeFirstResponder(nil)
	}
}


/**
Listen to local events.

- Important: Don't foret to call `.start()`.

```
eventMonitor = LocalEventMonitor(events: [.leftMouseDown, .rightMouseDown]) { event in
	// Do something

	return event
}.start()
```
*/
final class LocalEventMonitor {
	private let events: NSEvent.EventTypeMask
	private let callback: (NSEvent) -> NSEvent?
	private weak var monitor: AnyObject?

	init(events: NSEvent.EventTypeMask, callback: @escaping (NSEvent) -> NSEvent?) {
		self.events = events
		self.callback = callback
	}

	deinit {
		stop()
	}

	@discardableResult
	func start() -> Self {
		monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: callback) as AnyObject
		return self
	}

	func stop() {
		guard let monitor = monitor else {
			return
		}

		NSEvent.removeMonitor(monitor)
	}
}


extension NSEvent {
	static var modifiers: ModifierFlags {
		modifierFlags
			.intersection(.deviceIndependentFlagsMask)
			// We remove `capsLock` as it shouldn't affect the modifiers.
			// We remove `numericPad`/`function` as arrow keys trigger it, use `event.specialKeys` instead.
			.subtracting([.capsLock, .numericPad, .function])
	}

	/**
	Real modifiers.

	- Note: Prefer this over `.modifierFlags`.

	```
	// Check if Command is one of possible more modifiers keys
	event.modifiers.contains(.command)

	// Check if Command is the only modifier key
	event.modifiers == .command

	// Check if Command and Shift are the only modifiers
	event.modifiers == [.command, .shift]
	```
	*/
	var modifiers: ModifierFlags {
		modifierFlags
			.intersection(.deviceIndependentFlagsMask)
			// We remove `capsLock` as it shouldn't affect the modifiers.
			// We remove `numericPad`/`function` as arrow keys trigger it, use `event.specialKeys` instead.
			.subtracting([.capsLock, .numericPad, .function])
	}
}


extension NSSearchField {
	/// Clear the search field.
	func clear() {
		(cell as? NSSearchFieldCell)?.cancelButtonCell?.performClick(self)
	}
}


extension NSAlert {
	/// Show an alert as a window-modal sheet, or as an app-modal (window-independent) alert if the window is `nil` or not given.
	@discardableResult
	static func showModal(
		for window: NSWindow? = nil,
		message: String,
		informativeText: String? = nil,
		style: Style = .warning,
		icon: NSImage? = nil
	) -> NSApplication.ModalResponse {
		NSAlert(
			message: message,
			informativeText: informativeText,
			style: style,
			icon: icon
		).runModal(for: window)
	}

	convenience init(
		message: String,
		informativeText: String? = nil,
		style: Style = .warning,
		icon: NSImage? = nil
	) {
		self.init()
		self.messageText = message
		self.alertStyle = style
		self.icon = icon

		if let informativeText = informativeText {
			self.informativeText = informativeText
		}
	}

	/// Runs the alert as a window-modal sheet, or as an app-modal (window-independent) alert if the window is `nil` or not given.
	@discardableResult
	func runModal(for window: NSWindow? = nil) -> NSApplication.ModalResponse {
		guard let window = window else {
			return runModal()
		}

		beginSheetModal(for: window) { returnCode in
			NSApp.stopModal(withCode: returnCode)
		}

		return NSApp.runModal(for: window)
	}
}


extension NSEvent.ModifierFlags {
	var carbon: Int {
		var modifierFlags = 0

		if contains(.control) {
			modifierFlags |= controlKey
		}

		if contains(.option) {
			modifierFlags |= optionKey
		}

		if contains(.shift) {
			modifierFlags |= shiftKey
		}

		if contains(.command) {
			modifierFlags |= cmdKey
		}

		return modifierFlags
	}

	init(carbon: Int) {
		self.init()

		if carbon & controlKey == controlKey {
			insert(.control)
		}

		if carbon & optionKey == optionKey {
			insert(.option)
		}

		if carbon & shiftKey == shiftKey {
			insert(.shift)
		}

		if carbon & cmdKey == cmdKey {
			insert(.command)
		}
	}
}

/// :nodoc:
extension NSEvent.ModifierFlags: CustomStringConvertible {
	/**
	The string representation of the modifier flags.

	```
	print(NSEvent.ModifierFlags([.command, .shift]))
	//=> "⇧⌘"
	```
	*/
	public var description: String {
		var description = ""

		if contains(.control) {
			description += "⌃"
		}

		if contains(.option) {
			description += "⌥"
		}

		if contains(.shift) {
			description += "⇧"
		}

		if contains(.command) {
			description += "⌘"
		}

		return description
	}
}


extension NSEvent.SpecialKey {
	static let functionKeys: Set<Self> = [
		.f1,
		.f2,
		.f3,
		.f4,
		.f5,
		.f6,
		.f7,
		.f8,
		.f9,
		.f10,
		.f11,
		.f12,
		.f13,
		.f14,
		.f15,
		.f16,
		.f17,
		.f18,
		.f19,
		.f20,
		.f21,
		.f22,
		.f23,
		.f24,
		.f25,
		.f26,
		.f27,
		.f28,
		.f29,
		.f30,
		.f31,
		.f32,
		.f33,
		.f34,
		.f35
	]

	var isFunctionKey: Bool { Self.functionKeys.contains(self) }
}


enum AssociationPolicy {
	case assign
	case retainNonatomic
	case copyNonatomic
	case retain
	case copy

	var rawValue: objc_AssociationPolicy {
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

	subscript(index: AnyObject) -> T? {
		get {
			// Force-cast is fine here as we want it to fail loudly if we don't use the correct type.
			// swiftlint:disable:next force_cast
			objc_getAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque()) as! T?
		}
		set {
			objc_setAssociatedObject(index, Unmanaged.passUnretained(self).toOpaque(), newValue, policy.rawValue)
		}
	}
}


extension DispatchQueue {
	/**
	Label of the current dispatch queue.

	- Important: Only meant for debugging purposes.

	```
	DispatchQueue.currentQueueLabel
	//=> "com.apple.main-thread"
	```
	*/
	static var currentQueueLabel: String { String(cString: __dispatch_queue_get_label(nil)) }

	/// Whether the current queue is a `NSBackgroundActivityScheduler` task.
	static var isCurrentQueueNSBackgroundActivitySchedulerQueue: Bool { currentQueueLabel.hasPrefix("com.apple.xpc.activity.") }
}
