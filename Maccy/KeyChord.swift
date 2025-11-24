import AppKit.NSEvent
import KeyboardShortcuts
import Sauce

enum KeyChord: CaseIterable {
  static var pasteKey: Key { pasteMenuItem?.key ?? Key.v }
  static var pasteKeyModifiers: NSEvent.ModifierFlags { pasteMenuItem?.keyEquivalentModifierMask ?? .command }
  private static var pasteMenuItem: NSMenuItem? {
    NSApp.mainMenu?.items
      .flatMap { $0.submenu?.items ?? [] }
      .first { $0.action == #selector(NSText.paste) }
  }

  static var deleteKey: Key? { Sauce.shared.key(shortcut: .delete) }
  static var deleteModifiers: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .delete)?.modifiers }

  static var pinKey: Key? { Sauce.shared.key(shortcut: .pin) }
  static var pinModifiers: NSEvent.ModifierFlags? { KeyboardShortcuts.Shortcut(name: .pin)?.modifiers }

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
  case openPreferences
  case pinOrUnpin
  case selectCurrentItem
  case close
  case unknown

  init(_ event: NSEvent?) {
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

    self.init(key, modifierFlags)
  }

  init(_ key: Key, _ modifierFlags: NSEvent.ModifierFlags) { // swiftlint:disable:this cyclomatic_complexity
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
    case (.downArrow, []),
         (.downArrow, [.shift]),
         (.n, [.control]),
         (.n, [.control, .shift]),
         (.j, [.control]):
      self = .moveToNext
    case (.downArrow, _) where modifierFlags.contains(.command) || modifierFlags.contains(.option),
         (.n, [.control, .option]),
         (.pageDown, []):
      self = .moveToLast
    case (.upArrow, []),
         (.upArrow, [.shift]),
         (.p, [.control]),
         (.p, [.control, .shift]),
         (.k, [.control]):
      self = .moveToPrevious
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
    case (_, _) where !modifierFlags.isDisjoint(with: [.command, .control, .option]):
      self = .ignored
    default:
      self = .unknown
    }
  }
}
