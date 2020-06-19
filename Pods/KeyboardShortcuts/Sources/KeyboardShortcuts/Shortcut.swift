import Cocoa
import Carbon.HIToolbox

extension KeyboardShortcuts {
	/// A keyboard shortcut.
	public struct Shortcut: Hashable, Codable {
		/// Carbon modifiers are not always stored as the same number.
		/// For example, the system has `⌃F2` stored with the modifiers number `135168`, but if you press the keyboard shortcut, you get `4096`.
		private static func normalizeModifiers(_ carbonModifiers: Int) -> Int {
			NSEvent.ModifierFlags(carbon: carbonModifiers).carbon
		}

		/// The keyboard key of the shortcut.
		public var key: Key? { Key(rawValue: carbonKeyCode) }

		/// The modifier keys of the shortcut.
		public var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(carbon: carbonModifiers) }

		/// Low-level represetation of the key.
		/// You most likely don't need this.
		public let carbonKeyCode: Int

		/// Low-level representation of the modifier keys.
		/// You most likely don't need this.
		public let carbonModifiers: Int

		/// Initialize from a strongly-typed key and modifiers.
		public init(_ key: Key, modifiers: NSEvent.ModifierFlags = []) {
			self.init(
				carbonKeyCode: key.rawValue,
				carbonModifiers: modifiers.carbon
			)
		}

		/// Initialize from a key event.
		public init?(event: NSEvent) {
			guard event.isKeyEvent else {
				return nil
			}

			self.init(
				carbonKeyCode: Int(event.keyCode),
				carbonModifiers: event.modifierFlags.carbon
			)
		}

		/// Initialize from a keyboard shortcut stored by `Recorder` or `RecorderCocoa`.
		public init?(name: Name) {
			guard let shortcut = userDefaultsGet(name: name) else {
				return nil
			}

			self = shortcut
		}

		/// Initialize from a key code number and modifier code.
		/// You most likely don't need this.
		public init(carbonKeyCode: Int, carbonModifiers: Int = 0) {
			self.carbonKeyCode = carbonKeyCode
			self.carbonModifiers = Self.normalizeModifiers(carbonModifiers)
		}
	}
}

extension KeyboardShortcuts.Shortcut {
	/// System-defined keyboard shortcuts.
	static var system: [Self] { CarbonKeyboardShortcuts.system }

	/// Check whether the keyboard shortcut is already taken by the system.
	var isTakenBySystem: Bool { Self.system.contains(self) }
}

extension KeyboardShortcuts.Shortcut {
	/// Recursively finds a menu item in the given menu that has a matching key equivalent and modifier.
	func menuItemWithMatchingShortcut(in menu: NSMenu) -> NSMenuItem? {
		for item in menu.items {
			if
				keyToCharacter() == item.keyEquivalent,
				modifiers == item.keyEquivalentModifierMask
			{
				return item
			}

			if
				let submenu = item.submenu,
				let menuItem = menuItemWithMatchingShortcut(in: submenu)
			{
				return menuItem
			}
		}

		return nil
	}

	/// Returns a menu item in the app's main menu that has a matching key equivalent and modifier.
	var takenByMainMenu: NSMenuItem? {
		guard let mainMenu = NSApp.mainMenu else {
			return nil
		}

		return menuItemWithMatchingShortcut(in: mainMenu)
	}
}

private var keyToCharacterMapping: [KeyboardShortcuts.Key: String] = [
	.return: "↩",
	.delete: "⌫",
	.deleteForward: "⌦",
	.end: "↘",
	.escape: "⎋",
	.help: "?⃝",
	.home: "↖",
	.space: "⎵",
	.tab: "⇥",
	.pageUp: "⇞",
	.pageDown: "⇟",
	.upArrow: "↑",
	.rightArrow: "→",
	.downArrow: "↓",
	.leftArrow: "←",
	.f1: "F1",
	.f2: "F2",
	.f3: "F3",
	.f4: "F4",
	.f5: "F5",
	.f6: "F6",
	.f7: "F7",
	.f8: "F8",
	.f9: "F9",
	.f10: "F10",
	.f11: "F11",
	.f12: "F12",
	.f13: "F13",
	.f14: "F14",
	.f15: "F15",
	.f16: "F16",
	.f17: "F17",
	.f18: "F18",
	.f19: "F19",
	.f20: "F20"
]

private func stringFromKeyCode(_ keyCode: Int) -> String {
	String(format: "%C", keyCode)
}

private var keyToKeyEquivalentString: [KeyboardShortcuts.Key: String] = [
	.space: stringFromKeyCode(0x20),
	.f1: stringFromKeyCode(NSF1FunctionKey),
	.f2: stringFromKeyCode(NSF2FunctionKey),
	.f3: stringFromKeyCode(NSF3FunctionKey),
	.f4: stringFromKeyCode(NSF4FunctionKey),
	.f5: stringFromKeyCode(NSF5FunctionKey),
	.f6: stringFromKeyCode(NSF6FunctionKey),
	.f7: stringFromKeyCode(NSF7FunctionKey),
	.f8: stringFromKeyCode(NSF8FunctionKey),
	.f9: stringFromKeyCode(NSF9FunctionKey),
	.f10: stringFromKeyCode(NSF10FunctionKey),
	.f11: stringFromKeyCode(NSF11FunctionKey),
	.f12: stringFromKeyCode(NSF12FunctionKey),
	.f13: stringFromKeyCode(NSF13FunctionKey),
	.f14: stringFromKeyCode(NSF14FunctionKey),
	.f15: stringFromKeyCode(NSF15FunctionKey),
	.f16: stringFromKeyCode(NSF16FunctionKey),
	.f17: stringFromKeyCode(NSF17FunctionKey),
	.f18: stringFromKeyCode(NSF18FunctionKey),
	.f19: stringFromKeyCode(NSF19FunctionKey),
	.f20: stringFromKeyCode(NSF20FunctionKey)
]

extension KeyboardShortcuts.Shortcut {
	fileprivate func keyToCharacter() -> String? {
		// `TISCopyCurrentASCIICapableKeyboardLayoutInputSource` works on a background thread, but crashes when used in a `NSBackgroundActivityScheduler` task, so we guard against that. It only crashes when running from Xcode, not in release builds, but it's probably safest to not call it from a `NSBackgroundActivityScheduler` no matter what.
		assert(!DispatchQueue.isCurrentQueueNSBackgroundActivitySchedulerQueue, "This method cannot be used in a `NSBackgroundActivityScheduler` task")

		// Some characters cannot be automatically translated.
		if
			let key = key,
			let character = keyToCharacterMapping[key]
		{
			return character
		}

		guard
			let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
			let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
		else {
			return nil
		}

		let dataRef = unsafeBitCast(layoutDataPointer, to: CFData.self)
		let keyLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<CoreServices.UCKeyboardLayout>.self)
		var deadKeyState: UInt32 = 0
		let maxLength = 4
		var length = 0
		var characters = [UniChar](repeating: 0, count: maxLength)

		let error = CoreServices.UCKeyTranslate(
			keyLayout,
			UInt16(carbonKeyCode),
			UInt16(CoreServices.kUCKeyActionDisplay),
			UInt32(carbonModifiers),
			UInt32(LMGetKbdType()),
			OptionBits(CoreServices.kUCKeyTranslateNoDeadKeysBit),
			&deadKeyState,
			maxLength,
			&length,
			&characters
		)

		guard error == noErr else {
			return nil
		}

		return String(utf16CodeUnits: characters, count: length)
	}

	// This can be exposed if anyone needs it, but I prefer to keep the API surface small for now.
	/**
	This can be used to show the keyboard shortcut in a `NSMenuItem` by assigning it to `NSMenuItem#keyEquivalent`.

	- Note: Don't forget to also pass `.modifiers` to `NSMenuItem#keyEquivalentModifierMask`.
	*/
	var keyEquivalent: String {
		let keyString = keyToCharacter() ?? ""

		guard keyString.count <= 1 else {
			guard
				let key = self.key,
				let string = keyToKeyEquivalentString[key]
			else {
				return ""
			}

			return string
		}

		return keyString
	}
}

extension KeyboardShortcuts.Shortcut: CustomStringConvertible {
	/**
	The string representation of the keyboard shortcut.

	```
	print(Shortcut(.a, modifiers: [.command]))
	//=> "⌘A"
	```
	*/
	public var description: String {
		modifiers.description + (keyToCharacter()?.uppercased() ?? "�")
	}
}
