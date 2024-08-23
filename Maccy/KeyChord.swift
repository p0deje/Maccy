import AppKit
import KeyboardShortcuts
import Sauce
import SwiftUI

enum KeyChord: CaseIterable {
  static var pasteKey: Key { pasteMenuItem?.key ?? Key.v }
  static var pasteKeyModifiers: NSEvent.ModifierFlags { pasteMenuItem?.keyEquivalentModifierMask ?? .command }
  private static var pasteMenuItem: NSMenuItem? {
    NSApp.mainMenu?.items
      .flatMap { $0.submenu?.items ?? [] }
      .first { $0.action == #selector(NSText.paste) }
  }
  static var deleteKey: KeyEquivalent? { KeyboardShortcuts.Shortcut(name: .delete)?.toKeyEquivalent() }
  static var deleteModifiers: SwiftUI.EventModifiers? { KeyboardShortcuts.Shortcut(name: .delete)?.toEventModifiers() }

  static var pinKey: KeyEquivalent? { KeyboardShortcuts.Shortcut(name: .pin)?.toKeyEquivalent() }
  static var pinModifiers: SwiftUI.EventModifiers? { KeyboardShortcuts.Shortcut(name: .pin)?.toEventModifiers() }

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

  // TODO: why .delete doesn't work?
  init(_ key: KeyEquivalent, _ modifierFlags: SwiftUI.EventModifiers) {
    switch (key, modifierFlags.subtracting([.numericPad, .function])) {
    case (.delete, .init(arrayLiteral: [.command, .option])),
         (.backspace, .init(arrayLiteral: [.command, .option])):
      self = .clearHistory
    case (.delete, .init(arrayLiteral: [.command, .option, .shift])),
         (.backspace, .init(arrayLiteral: [.command, .option, .shift])):
      self = .clearHistoryAll
    case (.init("u"), .init(arrayLiteral: [.control])):
      self = .clearSearch
    case (KeyChord.deleteKey, KeyChord.deleteModifiers),
         (.backspace, KeyChord.deleteModifiers) where KeyChord.deleteKey == .delete:
      self = .deleteCurrentItem
    case (.init("h"), .init(arrayLiteral: [.control])):
      self = .deleteOneCharFromSearch
    case (.init("w"), .init(arrayLiteral: [.control])):
      self = .deleteLastWordFromSearch
    case (.downArrow, []),
         (.downArrow, .init(arrayLiteral: [.shift])),
         (.init("j"), .init(arrayLiteral: [.control])):
      self = .moveToNext
    case (.downArrow, _) where modifierFlags.contains(.command) || modifierFlags.contains(.option):
      self = .moveToLast
    case (.upArrow, []),
         (.upArrow, .init(arrayLiteral: [.shift])),
         (.init("k"), .init(arrayLiteral: [.control])):
      self = .moveToPrevious
    case (.upArrow, _) where modifierFlags.contains(.command) || modifierFlags.contains(.option):
      self = .moveToFirst
    case (KeyChord.pinKey, KeyChord.pinModifiers):
      self = .pinOrUnpin
    case (.init(","), .init(arrayLiteral: [.command])):
      self = .openPreferences
    case (.return, _) where !modifierFlags.isEmpty:
      self = .selectCurrentItem
    case (.escape, _):
      self = .close
    case (_, _) where !modifierFlags.isDisjoint(with: [.command, .control, .option]):
      self = .ignored
    default:
      self = .unknown
    }
  }
  // swiftlint:enable cyclomatic_complexity
}
