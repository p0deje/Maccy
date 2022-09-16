import AppKit
import KeyboardShortcuts
import Sauce

class GlobalHotKey {
  typealias Handler = () -> Void

  static public var key: Key? {
    guard let key = KeyboardShortcuts.Shortcut(name: .popup)?.key else {
      return nil
    }
    return Sauce.shared.key(for: key.rawValue)
  }
  static public var modifierFlags: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .popup)?.modifiers }

  private var handler: Handler

  init(_ handler: @escaping Handler) {
    self.handler = handler
    KeyboardShortcuts.onKeyDown(for: .popup, action: handler)
  }
}
