import AppKit
import Carbon
import KeyboardShortcuts
import Sauce
import SwiftUI

extension KeyEquivalent {
  static let backspace = KeyEquivalent("\u{7F}")
}

@available(macOS 11.0, *)
extension KeyboardShortcuts.Shortcut {
    func toKeyEquivalent() -> KeyEquivalent? {
        let carbonKeyCode = UInt16(self.carbonKeyCode)
        let maxNameLength = 4
        var nameBuffer = [UniChar](repeating: 0, count : maxNameLength)
        var nameLength = 0

        let modifierKeys = UInt32(0) // UInt32(alphaLock >> 8) & 0xFF // Caps Lock
        var deadKeys: UInt32 = 0
        let keyboardType = UInt32(LMGetKbdType())

        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            NSLog("Could not get keyboard layout data")
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        let osStatus = layoutData.withUnsafeBytes {
            UCKeyTranslate($0.bindMemory(to: UCKeyboardLayout.self).baseAddress, carbonKeyCode, UInt16(kUCKeyActionDown),
                           modifierKeys, keyboardType, UInt32(kUCKeyTranslateNoDeadKeysMask),
                           &deadKeys, maxNameLength, &nameLength, &nameBuffer)
        }
        guard osStatus == noErr else {
            NSLog("Code: 0x%04X  Status: %+i", carbonKeyCode, osStatus);
            return nil
        }

        return KeyEquivalent(Character(String(utf16CodeUnits: nameBuffer, count: nameLength)))
    }

  func toEventModifiers() -> SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []

        if self.modifiers.contains(NSEvent.ModifierFlags.command) {
            modifiers.update(with: EventModifiers.command)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.control) {
            modifiers.update(with: EventModifiers.control)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.option) {
            modifiers.update(with: EventModifiers.option)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.shift) {
            modifiers.update(with: EventModifiers.shift)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.capsLock) {
            modifiers.update(with: EventModifiers.capsLock)
        }

        if self.modifiers.contains(NSEvent.ModifierFlags.numericPad) {
            modifiers.update(with: EventModifiers.numericPad)
        }

        return modifiers
    }

}

//extension EventModifiers {
//  init(cocoaModifiers: NSEvent.ModifierFlags) {
//    let cModifiers = cocoaModifiers.intersection(.deviceIndependentFlagsMask)
//    var eModifiers = EventModifiers(arrayLiteral: [])
//    if cModifiers.contains(.command) {
//      eModifiers.insert(.command)
//    }
//    if cModifiers.contains(.control) {
//      eModifiers.insert(.control)
//    }
//    if cModifiers.contains(.shift) {
//      eModifiers.insert(.shift)
//    }
//    if cModifiers.contains(.option) {
//      eModifiers.insert(.option)
//    }
//
//    self = eModifiers
//  }
//}

enum KeyChord: CaseIterable {
  // Fetch paste from Edit / Paste menu item.
  // Fallback to ⌘V if unavailable.
  static var pasteKey: Key {
    (NSApp.delegate as? AppDelegate)?.pasteMenuItem.key ?? .v
  }
  static var pasteKeyModifiers: NSEvent.ModifierFlags {
    (NSApp.delegate as? AppDelegate)?.pasteMenuItem.keyEquivalentModifierMask ?? [.command]
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
  case hide
  case ignored
  case moveToNext
  case moveToLast
  case moveToPrevious
  case moveToFirst
  case openPreferences
  case paste
  case pinOrUnpin
  case selectCurrentItem
  case unknown

  // swiftlint:disable cyclomatic_complexity
  init(_ key: Key, _ modifierFlags: NSEvent.ModifierFlags) {
    switch (key, modifierFlags) {
    case (.delete, MenuFooter.clear.keyEquivalentModifierMask):
      self = .clearHistory
    case (.delete, MenuFooter.clearAll.keyEquivalentModifierMask):
      self = .clearHistoryAll
    case (.delete, [.command]), (.u, [.control]):
      self = .clearSearch
//    case (KeyChord.deleteKey, KeyChord.deleteModifiers):
//      self = .deleteCurrentItem
    case (.delete, []), (.h, [.control]):
      self = .deleteOneCharFromSearch
    case (.w, [.control]):
      self = .deleteLastWordFromSearch
    case (.j, [.control]):
      self = .moveToNext
    case (.k, [.control]):
      self = .moveToPrevious
//    case (KeyChord.pinKey, KeyChord.pinModifiers):
//      self = .pinOrUnpin
//    case (GlobalHotKey.key, GlobalHotKey.modifierFlags):
//      self = .hide
    case (.comma, MenuFooter.preferences.keyEquivalentModifierMask):
      self = .openPreferences
    case (KeyChord.pasteKey, KeyChord.pasteKeyModifiers):
      self = .paste
    case (.return, _), (.keypadEnter, _):
      self = .selectCurrentItem
    case (_, _) where Self.keysToSkip.contains(key) || !modifierFlags.isDisjoint(with: Self.modifiersToSkip):
      self = .ignored
    default:
      self = .unknown
    }
  }

  // TODO: why .delete doesn't work?
  init(_ key: KeyEquivalent, _ modifierFlags: SwiftUI.EventModifiers) {
    switch (key, modifierFlags.subtracting([.numericPad, .function])) {
    case (.delete, .init(arrayLiteral: [.command, .option])),
         (.backspace, .init(arrayLiteral: [.command, .option])):
      self = .clearHistory
    case (.delete, .init(arrayLiteral: [.command, .option, .shift])),
         (.backspace, .init(arrayLiteral: [.command, .option, .shift])):
      self = .clearHistoryAll
    case (.delete, .init(arrayLiteral: [.command])),
         (.backspace, .init(arrayLiteral: [.command])),
         (.init("u"), .init(arrayLiteral: [.control])):
      self = .clearSearch
    case (KeyChord.deleteKey, KeyChord.deleteModifiers),
         (.backspace, KeyChord.deleteModifiers) where KeyChord.deleteKey == .delete:
      self = .deleteCurrentItem
    case (.delete, .init(arrayLiteral: [])),
         (.backspace, .init(arrayLiteral: [])),
         (.init("h"), .init(arrayLiteral: [.control])):
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
    case (.init(","), MenuFooter.preferences.eventModifiers):
      self = .openPreferences
    case (.return, _):
      self = .selectCurrentItem
    case (_, _) where !modifierFlags.isDisjoint(with: [.command, .control, .option]):
      self = .ignored
    default:
      self = .unknown
    }
  }
  // swiftlint:enable cyclomatic_complexity

  static let keysToSkip = [
    Key.home,
    Key.pageUp,
    Key.pageDown,
    Key.end,
    Key.downArrow,
    Key.leftArrow,
    Key.rightArrow,
    Key.upArrow,
    Key.escape,
    Key.tab,
    Key.f1,
    Key.f2,
    Key.f3,
    Key.f4,
    Key.f5,
    Key.f6,
    Key.f7,
    Key.f8,
    Key.f9,
    Key.f10,
    Key.f11,
    Key.f12,
    Key.f13,
    Key.f14,
    Key.f15,
    Key.f16,
    Key.f17,
    Key.f18,
    Key.f19,
    Key.eisu,
    Key.kana
  ]
  private static let modifiersToSkip = NSEvent.ModifierFlags([
    .command,
    .control,
    .option
  ])
}
