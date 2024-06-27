import AppKit
import Defaults
import SwiftUI

extension HistoryMenuItem {
  class PasteWithoutFormattingMenuItem: HistoryMenuItem {
    static var keyEquivalentModifierMask: NSEvent.ModifierFlags {
      if Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault] {
        return NSEvent.ModifierFlags([.command, .shift])
      } else if !Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault] {
        return .option
      } else if !Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault] {
        return NSEvent.ModifierFlags([.option, .shift])
      } else {
        return .command
      }
    }

    static var modifiers: EventModifiers {
      if Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault] {
        return EventModifiers(arrayLiteral: [.command, .shift])
      } else if !Defaults[.pasteByDefault] && Defaults[.removeFormattingByDefault] {
        return .option
      } else if !Defaults[.pasteByDefault] && !Defaults[.removeFormattingByDefault] {
        return EventModifiers(arrayLiteral: [.option, .shift])
      } else {
        return .command
      }
    }

    override func select() {
//      clipboard.copy(item, removeFormatting: true)
//      clipboard.paste()
    }

    override func alternate() {
      keyEquivalentModifierMask = PasteWithoutFormattingMenuItem.keyEquivalentModifierMask

      if !Defaults[.pasteByDefault] || !Defaults[.removeFormattingByDefault] {
        super.alternate()
      }
    }
  }
}
