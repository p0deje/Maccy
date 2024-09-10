import KeyboardShortcuts
import Sauce

extension Sauce {
  func key(shortcut: KeyboardShortcuts.Name) -> Key? {
    if let shortcut = KeyboardShortcuts.Shortcut(name: shortcut) {
      return Sauce.shared.key(for: shortcut.carbonKeyCode)
    } else {
      return nil
    }
  }
}
