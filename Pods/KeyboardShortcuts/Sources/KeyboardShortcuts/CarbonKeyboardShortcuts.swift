import Carbon.HIToolbox

private func carbonKeyboardShortcutsEventHandler(eventHandlerCall: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
	CarbonKeyboardShortcuts.handleEvent(event)
}

enum CarbonKeyboardShortcuts {
	private final class HotKey {
		let shortcut: KeyboardShortcuts.Shortcut
		let carbonHotKeyId: Int
		let carbonHotKey: EventHotKeyRef
		let onKeyDown: (KeyboardShortcuts.Shortcut) -> Void
		let onKeyUp: (KeyboardShortcuts.Shortcut) -> Void

		init(
			shortcut: KeyboardShortcuts.Shortcut,
			carbonHotKeyID: Int,
			carbonHotKey: EventHotKeyRef,
			onKeyDown: @escaping (KeyboardShortcuts.Shortcut) -> Void,
			onKeyUp: @escaping (KeyboardShortcuts.Shortcut) -> Void
		) {
			self.shortcut = shortcut
			self.carbonHotKeyId = carbonHotKeyID
			self.carbonHotKey = carbonHotKey
			self.onKeyDown = onKeyDown
			self.onKeyUp = onKeyUp
		}
	}

	private static var hotKeys = [Int: HotKey]()

	// `SSKS` is just short for `Sindre Sorhus Keyboard Shortcuts`.
	private static let hotKeySignature = UTGetOSTypeFromString("SSKS" as CFString)

	private static var hotKeyId = 0
	private static var eventHandler: EventHandlerRef?

	private static func setUpEventHandlerIfNeeded() {
		guard
			eventHandler == nil,
			let dispatcher = GetEventDispatcherTarget()
		else {
			return
		}

		let eventSpecs = [
			EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
			EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
		]

		InstallEventHandler(
			dispatcher,
			carbonKeyboardShortcutsEventHandler,
			eventSpecs.count,
			eventSpecs,
			nil,
			&eventHandler
		)
	}

	static func register(
		_ shortcut: KeyboardShortcuts.Shortcut,
		onKeyDown: @escaping (KeyboardShortcuts.Shortcut) -> Void,
		onKeyUp: @escaping (KeyboardShortcuts.Shortcut) -> Void
	) {
		hotKeyId += 1

		var eventHotKey: EventHotKeyRef?
		let registerError = RegisterEventHotKey(
			UInt32(shortcut.carbonKeyCode),
			UInt32(shortcut.carbonModifiers),
			EventHotKeyID(signature: hotKeySignature, id: UInt32(hotKeyId)),
			GetEventDispatcherTarget(),
			0,
			&eventHotKey
		)

		guard
			registerError == noErr,
			let carbonHotKey = eventHotKey
		else {
			return
		}

		hotKeys[hotKeyId] = HotKey(
			shortcut: shortcut,
			carbonHotKeyID: hotKeyId,
			carbonHotKey: carbonHotKey,
			onKeyDown: onKeyDown,
			onKeyUp: onKeyUp
		)

		setUpEventHandlerIfNeeded()
	}

	private static func unregisterHotKey(_ hotKey: HotKey) {
		UnregisterEventHotKey(hotKey.carbonHotKey)
		hotKeys.removeValue(forKey: hotKey.carbonHotKeyId)
	}

	static func unregister(_ shortcut: KeyboardShortcuts.Shortcut) {
		for hotKey in hotKeys.values where hotKey.shortcut == shortcut {
			unregisterHotKey(hotKey)
		}
	}

	static func unregisterAll() {
		for hotKey in hotKeys.values {
			unregisterHotKey(hotKey)
		}
	}

	fileprivate static func handleEvent(_ event: EventRef?) -> OSStatus {
		guard let event = event else {
			return OSStatus(eventNotHandledErr)
		}

		var eventHotKeyId = EventHotKeyID()
		let error = GetEventParameter(
			event,
			UInt32(kEventParamDirectObject),
			UInt32(typeEventHotKeyID),
			nil,
			MemoryLayout<EventHotKeyID>.size,
			nil,
			&eventHotKeyId
		)

		guard error == noErr else {
			return error
		}

		guard
			eventHotKeyId.signature == hotKeySignature,
			let hotKey = hotKeys[Int(eventHotKeyId.id)]
		else {
			return OSStatus(eventNotHandledErr)
		}

		switch Int(GetEventKind(event)) {
		case kEventHotKeyPressed:
			hotKey.onKeyDown(hotKey.shortcut)
			return noErr
		case kEventHotKeyReleased:
			hotKey.onKeyUp(hotKey.shortcut)
			return noErr
		default:
			break
		}

		return OSStatus(eventNotHandledErr)
	}
}

extension CarbonKeyboardShortcuts {
	static var system: [KeyboardShortcuts.Shortcut] {
		var shortcutsUnmanaged: Unmanaged<CFArray>?
		guard
			CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr,
			let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]]
		else {
			assertionFailure("Could not get system keyboard shortcuts")
			return []
		}

		return shortcuts.compactMap {
			guard
				($0[kHISymbolicHotKeyEnabled] as? Bool) == true,
				let carbonKeyCode = $0[kHISymbolicHotKeyCode] as? Int,
				let carbonModifiers = $0[kHISymbolicHotKeyModifiers] as? Int
			else {
				return nil
			}

			return KeyboardShortcuts.Shortcut(
				carbonKeyCode: carbonKeyCode,
				carbonModifiers: carbonModifiers
			)
		}
	}
}
