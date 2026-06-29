import AppKit.NSEvent
import KeyboardShortcuts
import Sauce

/// Maps a key event into a high-level keyboard action understood by the UI.
enum KeyChord: CaseIterable {
  /// The key bound to the system Paste command (defaults to `v`).
  @MainActor static var pasteKey: Key { pasteMenuItem?.key ?? Key.v }
  /// The modifier flags bound to the system Paste command (defaults to command).
  @MainActor static var pasteKeyModifiers: NSEvent.ModifierFlags {
    pasteMenuItem?.keyEquivalentModifierMask ?? .command
  }
  /// The Paste menu item discovered in the main menu, if present.
  @MainActor private static var pasteMenuItem: NSMenuItem? {
    NSApp.mainMenu?.items
      .flatMap { $0.submenu?.items ?? [] }
      .first { $0.action == #selector(NSText.paste) }
  }

  /// The key bound to the Delete-item shortcut, if assigned.
  static var deleteKey: Key? { Sauce.shared.key(shortcut: .delete) }
  /// The modifier flags bound to the Delete-item shortcut, if assigned.
  static var deleteModifiers: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .delete)?.modifiers }

  /// The key bound to the Pin shortcut, if assigned.
  static var pinKey: Key? { Sauce.shared.key(shortcut: .pin) }
  /// The modifier flags bound to the Pin shortcut, if assigned.
  static var pinModifiers: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .pin)?.modifiers }

  /// The key bound to the toggle-preview shortcut, if assigned.
  static var previewKey: Key? { Sauce.shared.key(shortcut: .togglePreview) }
  /// The modifier flags bound to the toggle-preview shortcut, if assigned.
  static var previewModifiers: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .togglePreview)?.modifiers }

  case clearHistory
  case clearHistoryAll
  case clearSearch
  case deleteCurrentItem
  case deleteOneCharFromSearch
  case deleteLastWordFromSearch
  case ignored
  case moveToNext
  case moveToLast
  case moveToPrevious
  case moveToFirst
  case extendToNext
  case extendToLast
  case extendToPrevious
  case extendToFirst
  case openPreferences
  case pinOrUnpin
  case selectCurrentItem
  case close
  case togglePreview
  case unknown

  /// Resolves a key-down event into a chord, accounting for the active keyboard
  /// layout and whether multi-selection is enabled.
  init(_ event: NSEvent?, multiSelectionEnabled: Bool) {
    guard let event, event.type == .keyDown else {
      self = .unknown
      return
    }

    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
    var key: Key?

    if KeyboardLayout.current.commandSwitchesToQWERTY, modifierFlags.contains(.command) {
      key = Key(QWERTYKeyCode: Int(event.keyCode))
    } else {
      key = Sauce.shared.key(for: Int(event.keyCode))
    }

    guard let key else {
      self = .unknown
      return
    }

    self.init(key, modifierFlags, multiSelectionEnabled: multiSelectionEnabled)
  }

  // Resolves an already-decoded key and modifier set into a chord.
  // swiftlint:disable:next cyclomatic_complexity
  init(_ key: Key, _ modifierFlags: NSEvent.ModifierFlags, multiSelectionEnabled: Bool) {
    switch (key, modifierFlags) {
    case (.delete, [.command, .option]):
      self = .clearHistory
    case (.delete, [.command, .option, .shift]):
      self = .clearHistoryAll
    case (.u, [.control]):
      self = .clearSearch
    case (KeyChord.deleteKey, KeyChord.deleteModifiers):
      self = .deleteCurrentItem
    case (.h, [.control]):
      self = .deleteOneCharFromSearch
    case (.w, [.control]):
      self = .deleteLastWordFromSearch
    case (.downArrow, [.shift]),
         (.n, [.control, .shift]):
      self = multiSelectionEnabled ? .extendToNext : .moveToNext
    case (.downArrow, []),
         (.n, [.control]),
         (.j, [.control]):
      self = .moveToNext
    case (.downArrow, [.command, .shift]),
         (.downArrow, [.option, .shift]),
         (.n, [.control, .option, .shift]):
      self = multiSelectionEnabled ? .extendToLast : .moveToLast
    case (.downArrow, _) where modifierFlags.contains(.command) || modifierFlags.contains(.option),
         (.n, [.control, .option]),
         (.pageDown, []):
      self = .moveToLast
    case (.upArrow, [.shift]),
         (.p, [.control, .shift]):
      self = multiSelectionEnabled ? .extendToPrevious : .moveToPrevious
    case (.upArrow, []),
         (.p, [.control]),
         (.k, [.control]):
      self = .moveToPrevious
    case (.upArrow, [.command, .shift]),
         (.upArrow, [.option, .shift]),
         (.p, [.control, .option, .shift]):
      self = multiSelectionEnabled ? .extendToFirst : .moveToFirst
    case (.upArrow, _) where modifierFlags.contains(.command) || modifierFlags.contains(.option),
         (.p, [.control, .option]),
         (.pageUp, []):
      self = .moveToFirst
    case (KeyChord.pinKey, KeyChord.pinModifiers):
      self = .pinOrUnpin
    case (.comma, [.command]):
      self = .openPreferences
    case (.return, _),
         (.keypadEnter, _):
      self = .selectCurrentItem
    case (.escape, _):
      self = .close
    case (KeyChord.previewKey, KeyChord.previewModifiers):
      self = .togglePreview
    case (_, _) where !modifierFlags.isDisjoint(with: [.command, .control, .option]):
      self = .ignored
    default:
      self = .unknown
    }
  }
}
