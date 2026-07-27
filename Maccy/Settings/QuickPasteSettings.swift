import AppKit
import Defaults
import KeyboardShortcuts

enum QuickPasteSettings {
  private static let numberKeys: [KeyboardShortcuts.Key] = [.one, .two, .three, .four, .five]

  static func bootstrap() {
    guard KeyboardShortcuts.getShortcut(for: .quickPasteBase) == nil,
          let first = KeyboardShortcuts.getShortcut(for: .quickPaste1) else {
      return
    }

    KeyboardShortcuts.setShortcut(
      KeyboardShortcuts.Shortcut(.one, modifiers: first.modifiers),
      for: .quickPasteBase
    )
  }

  static func applyModifiers(from shortcut: KeyboardShortcuts.Shortcut?) {
    guard let shortcut else { return }

    let modifiers = shortcut.modifiers
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])

    KeyboardShortcuts.setShortcut(
      KeyboardShortcuts.Shortcut(.one, modifiers: modifiers),
      for: .quickPasteBase
    )

    for (index, name) in KeyboardShortcuts.Name.quickPastes.enumerated() {
      KeyboardShortcuts.setShortcut(
        KeyboardShortcuts.Shortcut(numberKeys[index], modifiers: modifiers),
        for: name
      )
    }

    if Defaults[.enableQuickPaste] {
      KeyboardShortcuts.enable(KeyboardShortcuts.Name.quickPastes)
    }
  }

  static func resetToDefaults() {
    KeyboardShortcuts.reset(.quickPasteBase)
    KeyboardShortcuts.reset(KeyboardShortcuts.Name.quickPastes)
  }
}
