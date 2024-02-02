import AppKit

extension HistoryMenuItem {
  class PasteWithoutFormattingMenuItem: HistoryMenuItem {
    static var keyEquivalentModifierMask: NSEvent.ModifierFlags {
      if UserDefaults.standard.pasteByDefault && !UserDefaults.standard.removeFormattingByDefault {
        return NSEvent.ModifierFlags([.command, .shift])
      } else if !UserDefaults.standard.pasteByDefault && UserDefaults.standard.removeFormattingByDefault {
        return .option
      } else if !UserDefaults.standard.pasteByDefault && !UserDefaults.standard.removeFormattingByDefault {
        return NSEvent.ModifierFlags([.option, .shift])
      } else {
        return .command
      }
    }

    override func select() {
      clipboard.copy(item, removeFormatting: true)
      clipboard.paste()
    }

    override func alternate() {
      keyEquivalentModifierMask = PasteWithoutFormattingMenuItem.keyEquivalentModifierMask

      if !UserDefaults.standard.pasteByDefault || !UserDefaults.standard.removeFormattingByDefault {
        isAlternate = true
      }
    }
  }
}
