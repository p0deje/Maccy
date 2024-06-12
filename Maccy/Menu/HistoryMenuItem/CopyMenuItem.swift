import AppKit
import Defaults

extension HistoryMenuItem {
  class CopyMenuItem: HistoryMenuItem {
    static var keyEquivalentModifierMask: NSEvent.ModifierFlags {
      if Defaults[.pasteByDefault] {
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

      if Defaults[.pasteByDefault] {
        super.alternate()
      }
    }
  }
}
