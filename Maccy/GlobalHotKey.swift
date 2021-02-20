import AppKit
import KeyboardShortcuts

class GlobalHotKey {
  typealias Handler = () -> Void

  static public var key: KeyboardShortcuts.Key? { KeyboardShortcuts.Shortcut(name: .popup)?.key }
  static public var modifierFlags: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .popup)?.modifiers }

  private var popupHandler: Handler
  private var privateModeHandler: Handler


  init(_ popupHandler: @escaping Handler, _ privateModeHandler: @escaping Handler) {
    self.popupHandler = popupHandler
    self.privateModeHandler = privateModeHandler
    KeyboardShortcuts.onKeyDown(for: .popup, action: popupHandler)
    KeyboardShortcuts.onKeyDown(for: .privateMode, action: privateModeHandler)
  }
}
