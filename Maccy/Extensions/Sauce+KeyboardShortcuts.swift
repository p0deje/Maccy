import KeyboardShortcuts
import Sauce

extension Sauce {
  /// Resolves the currently bound `Sauce.Key` for the given keyboard shortcut name.
  ///
  /// Returns `nil` when no shortcut is bound to `shortcut`.
  func key(shortcut: KeyboardShortcuts.Name) -> Key? {
    if let shortcut = KeyboardShortcuts.Shortcut(name: shortcut) {
      return Sauce.shared.key(for: shortcut.carbonKeyCode)
    } else {
      return nil
    }
  }
}
