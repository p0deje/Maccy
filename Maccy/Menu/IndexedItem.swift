import AppKit

extension Menu {
  class IndexedItem: NSObject {
    var title: String { item.title ?? "" }
    var value: String
    var item: HistoryItem!
    var menuItems: [HistoryMenuItem]
    var popoverAnchor: NSMenuItem?

    var menuItemCount : Int {
      menuItems.count
    }

    init(item: HistoryItem, clipboard: Clipboard) {
      self.item = item
      self.value = item.generateContentString(item.getContents())
      self.menuItems = IndexedItem.buildMenuItems(for: item, withClipboard: clipboard)
      if #unavailable(macOS 14) {
        self.popoverAnchor = HistoryMenuItem.PreviewMenuItem()
      }
    }

    private static func buildMenuItems(for item: HistoryItem, withClipboard clipboard : Clipboard) -> [HistoryMenuItem] {
      let menuItems = [
        HistoryMenuItem.CopyMenuItem(item: item, clipboard: clipboard),
        HistoryMenuItem.PasteMenuItem(item: item, clipboard: clipboard),
        HistoryMenuItem.PasteWithoutFormattingMenuItem(item: item, clipboard: clipboard)
      ]

      return menuItems.sorted(by: { !$0.isAlternate && $1.isAlternate })
    }
  }
}
