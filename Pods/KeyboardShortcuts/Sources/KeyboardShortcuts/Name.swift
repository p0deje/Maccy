extension KeyboardShortcuts {
	/**
	The strongly-typed name of the keyboard shortcut.

	After registering it, you can use it in, for example, `KeyboardShortcut.Recorder` and `KeyboardShortcut.onKeyUp()`.

	```
	import KeyboardShortcuts

	extension KeyboardShortcuts.Name {
		static let toggleUnicornMode = Name("toggleUnicornMode")
	}
	```
	*/
	public struct Name: Hashable {
		// These make it possible to use the types without the namespace.
		// `extension KeyboardShortcuts.Name { static let x = Name("x") }`.
		/// :nodoc:
		public typealias Name = KeyboardShortcuts.Name
		/// :nodoc:
		public typealias Shortcut = KeyboardShortcuts.Shortcut

		public let rawValue: String

		/**
		- Parameter name: Name of the shortcut.
		- Parameter default: Optional default key combination for the shortcut. Do not set this unless it's essential. Users find it annoying when random apps steal their existing keyboard shortcuts. It's generally better to show a welcome screen on the first app launch that lets the user set the shortcut.
		*/
		public init(_ name: String, default defaultShortcut: Shortcut? = nil) {
			self.rawValue = name

			if
				let defaultShortcut = defaultShortcut,
				!userDefaultsContains(name: self)
			{
				userDefaultsSet(name: self, shortcut: defaultShortcut)
			}
		}
	}
}

extension KeyboardShortcuts.Name: RawRepresentable {
	/// :nodoc:
	public init?(rawValue: String) {
		self.init(rawValue)
	}
}
