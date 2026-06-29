import AppKit.NSEvent
import Defaults
import Sauce

/// A keyboard shortcut option shown in the popup footer (e.g. paste variants).
struct KeyShortcut: Identifiable {
  /// Builds the three shortcut variants for a character: plain, option, and
  /// the configured paste/option-shift combination.
  static func create(character: String) -> [KeyShortcut] {
    let key = Key(character: character, virtualKeyCode: nil)
    return [
      KeyShortcut(key: key),
      KeyShortcut(key: key, modifierFlags: [.option]),
      KeyShortcut(key: key, modifierFlags: [Defaults[.pasteByDefault] ? .command : .option, .shift])
    ]
  }

  let id = UUID()

  var key: Key?
  var modifierFlags: NSEvent.ModifierFlags = [.command]

  /// Human-readable rendering of the shortcut (modifiers plus capital key).
  var description: String {
    guard let key, let character = Sauce.shared.currentASCIICapableCharacter(
      for: Int(Sauce.shared.keyCode(for: key)),
      cocoaModifiers: []
    ) else {
      return ""
    }

    return "\(modifierFlags.description)\(character.capitalized)"
  }

  /// Returns true when this shortcut should be shown given the set of all
  /// shortcuts and the currently pressed modifiers.
  func isVisible(_ all: [KeyShortcut], _ pressedModifierFlags: NSEvent.ModifierFlags) -> Bool {
    if all.count == 1 {
      return true
    }

    if modifierFlags == [.command], pressedModifierFlags.isEmpty {
      return true
    }

    if modifierFlags == [.command], !pressedModifierFlags.isEmpty,
       !all.contains(where: { $0.id != id && $0.modifierFlags == pressedModifierFlags }) {
      return true
    }

    return modifierFlags == pressedModifierFlags
  }
}
