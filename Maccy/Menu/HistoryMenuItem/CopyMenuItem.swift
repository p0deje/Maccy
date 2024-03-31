import AppKit

extension HistoryMenuItem {
  class CopyMenuItem: HistoryMenuItem {
    static var keyEquivalentModifierMask: NSEvent.ModifierFlags {
      if UserDefaults.standard.pasteByDefault {
        return .option
      } else {
        return .command
      }
    }

    override func select() {
      clipboard.copy(item)
    }

    override func alternate() {
      keyEquivalentModifierMask = CopyMenuItem.keyEquivalentModifierMask

      if UserDefaults.standard.pasteByDefault {
        super.alternate()
      }
    }
  }
}
