import KeyboardShortcuts

class GlobalHotKey {
  typealias Handler = () -> Void

  static public var key: KeyboardShortcuts.Key? { KeyboardShortcuts.Shortcut(name: .popup)?.key }
  static public var modifierFlags: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .popup)?.modifiers }

  private var handler: Handler

  init(_ handler: @escaping Handler) {
    self.handler = handler
    KeyboardShortcuts.onKeyDown(for: .popup, action: handler)
  }
}
