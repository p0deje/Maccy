import AppKit

extension HistoryMenuItem {
  class PasteMenuItem: HistoryMenuItem {
    static var keyEquivalentModifierMask: NSEvent.ModifierFlags {
      if UserDefaults.standard.pasteByDefault && UserDefaults.standard.removeFormattingByDefault {
        return NSEvent.ModifierFlags([.command, .shift])
      } else if !UserDefaults.standard.pasteByDefault && UserDefaults.standard.removeFormattingByDefault {
        return NSEvent.ModifierFlags([.option, .shift])
      } else if !UserDefaults.standard.pasteByDefault && !UserDefaults.standard.removeFormattingByDefault {
        return .option
      } else {
        return .command
      }
    }

    override func select() {
      clipboard.copy(item)
      clipboard.paste()
    }

    override func alternate() {
      keyEquivalentModifierMask = PasteMenuItem.keyEquivalentModifierMask

      if !UserDefaults.standard.pasteByDefault || UserDefaults.standard.removeFormattingByDefault {
        super.alternate()
      }
    }
  }
}
