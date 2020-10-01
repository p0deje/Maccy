import Cocoa

/**
Global keyboard shortcuts for your macOS app.
*/
public enum KeyboardShortcuts {
	/// :nodoc:
	public typealias KeyAction = () -> Void

	private static var registeredShortcuts = Set<Shortcut>()

	// Not currently used. For the future.
	private static var keyDownHandlers = [Shortcut: [KeyAction]]()
	private static var keyUpHandlers = [Shortcut: [KeyAction]]()

	private static var userDefaultsKeyDownHandlers = [Name: [KeyAction]]()
	private static var userDefaultsKeyUpHandlers = [Name: [KeyAction]]()

	private static func register(_ shortcut: Shortcut) {
		guard !registeredShortcuts.contains(shortcut) else {
			return
		}

		CarbonKeyboardShortcuts.register(
			shortcut,
			onKeyDown: handleOnKeyDown,
			onKeyUp: handleOnKeyUp
		)

		registeredShortcuts.insert(shortcut)
	}

	private static func unregister(_ shortcut: Shortcut) {
		CarbonKeyboardShortcuts.unregister(shortcut)
		registeredShortcuts.remove(shortcut)
	}

	// TODO: Doc comment and make this public.
	static func unregisterAll() {
		CarbonKeyboardShortcuts.unregisterAll()
		registeredShortcuts.removeAll()

		// TODO: Should remove user defaults too.
	}

	// TODO: Also add `.isEnabled(_ name: Name)`.
	/**
	Disable a keyboard shortcut.
	*/
	public static func disable(_ name: Name) {
		guard let shortcut = userDefaultsGet(name: name) else {
			return
		}

		unregister(shortcut)
	}

	/**
	Enable a disabled keyboard shortcut.
	*/
	public static func enable(_ name: Name) {
		guard let shortcut = userDefaultsGet(name: name) else {
			return
		}

		register(shortcut)
	}

	private static func handleOnKeyDown(_ shortcut: Shortcut) {
		if let handlers = keyDownHandlers[shortcut] {
			for handler in handlers {
				handler()
			}
		}

		for (name, handlers) in userDefaultsKeyDownHandlers {
			guard userDefaultsGet(name: name) == shortcut else {
				continue
			}

			for handler in handlers {
				handler()
			}
		}
	}

	private static func handleOnKeyUp(_ shortcut: Shortcut) {
		if let handlers = keyUpHandlers[shortcut] {
			for handler in handlers {
				handler()
			}
		}

		for (name, handlers) in userDefaultsKeyUpHandlers {
			guard userDefaultsGet(name: name) == shortcut else {
				continue
			}

			for handler in handlers {
				handler()
			}
		}
	}

	/**
	Listen to the keyboard shortcut with the given name being pressed.

	You can register multiple listeners.

	You can safely call this even if the user has not yet set a keyboard shortcut. It will just be inactive until they do.

	```
	import Cocoa
	import KeyboardShortcuts

	@NSApplicationMain
	final class AppDelegate: NSObject, NSApplicationDelegate {
		func applicationDidFinishLaunching(_ notification: Notification) {
			KeyboardShortcuts.onKeyDown(for: .toggleUnicornMode) {
				self.isUnicornMode.toggle()
			}
		}
	}
	```
	*/
	public static func onKeyDown(for name: Name, action: @escaping KeyAction) {
		if userDefaultsKeyDownHandlers[name] == nil {
			userDefaultsKeyDownHandlers[name] = []
		}

		userDefaultsKeyDownHandlers[name]?.append(action)

		// If the keyboard shortcut already exist, we register it.
		if let shortcut = userDefaultsGet(name: name) {
			register(shortcut)
		}
	}

	/**
	Listen to the keyboard shortcut with the given name being pressed.

	You can register multiple listeners.

	You can safely call this even if the user has not yet set a keyboard shortcut. It will just be inactive until they do.

	```
	import Cocoa
	import KeyboardShortcuts

	@NSApplicationMain
	final class AppDelegate: NSObject, NSApplicationDelegate {
		func applicationDidFinishLaunching(_ notification: Notification) {
			KeyboardShortcuts.onKeyUp(for: .toggleUnicornMode) {
				self.isUnicornMode.toggle()
			}
		}
	}
	```
	*/
	public static func onKeyUp(for name: Name, action: @escaping KeyAction) {
		if userDefaultsKeyUpHandlers[name] == nil {
			userDefaultsKeyUpHandlers[name] = []
		}

		userDefaultsKeyUpHandlers[name]?.append(action)

		// If the keyboard shortcut already exist, we register it.
		if let shortcut = userDefaultsGet(name: name) {
			register(shortcut)
		}
	}

	private static let userDefaultsPrefix = "KeyboardShortcuts_"

	private static func userDefaultsKey(for shortcutName: Name) -> String { "\(userDefaultsPrefix)\(shortcutName.rawValue)"
	}

	static func userDefaultsDidChange(name: Name) {
		// TODO: Use proper UserDefaults observation instead of this.
		NotificationCenter.default.post(name: .shortcutByNameDidChange, object: nil, userInfo: ["name": name])
	}

	// TODO: Should these be on `Shortcut` instead?
	static func userDefaultsGet(name: Name) -> Shortcut? {
		guard
			let data = UserDefaults.standard.string(forKey: userDefaultsKey(for: name))?.data(using: .utf8),
			let decoded = try? JSONDecoder().decode(Shortcut.self, from: data)
		else {
			return nil
		}

		return decoded
	}

	static func userDefaultsSet(name: Name, shortcut: Shortcut) {
		guard let encoded = try? JSONEncoder().encode(shortcut).string else {
			return
		}

		if let oldShortcut = userDefaultsGet(name: name) {
			unregister(oldShortcut)
		}

		register(shortcut)
		UserDefaults.standard.set(encoded, forKey: userDefaultsKey(for: name))
		userDefaultsDidChange(name: name)
	}

	static func userDefaultsRemove(name: Name) {
		guard let shortcut = userDefaultsGet(name: name) else {
			return
		}

		UserDefaults.standard.set(false, forKey: userDefaultsKey(for: name))
		unregister(shortcut)
		userDefaultsDidChange(name: name)
	}

	static func userDefaultsContains(name: Name) -> Bool {
		UserDefaults.standard.object(forKey: userDefaultsKey(for: name)) != nil
	}
}

extension Notification.Name {
	static let shortcutByNameDidChange = Self("KeyboardShortcuts_shortcutByNameDidChange")
}
