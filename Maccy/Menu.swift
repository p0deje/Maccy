import AppKit

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
class Menu: NSMenu, NSMenuDelegate {
  public let maxHotKey = 9
  public let menuWidth = 300

  private let search = Search()

  private var clipboard: Clipboard!
  private var history: History!
  private var historyItems: [HistoryMenuItem] = []

  required init(coder decoder: NSCoder) {
    super.init(coder: decoder)
  }

  init(history: History, clipboard: Clipboard) {
    super.init(title: "Maccy")
    self.history = history
    self.clipboard = clipboard
    self.delegate = self
    self.minimumWidth = CGFloat(menuWidth)
  }

  func menuWillOpen(_ menu: NSMenu) {
    setKeyEquivalents(historyItems)
    highlight(historyItems.first)
  }

  func prepend(_ entry: String) {
    removeDuplicateItems(entry)

    let copyHistoryItem = HistoryMenuItem(title: entry, onSelected: copy(_:))
    let pasteHistoryItem = HistoryMenuItem(title: entry, onSelected: copyAndPaste(_:))

    if UserDefaults.standard.pasteByDefault {
      alternate(copyHistoryItem)
      prependHistoryItems(pasteHistoryItem, copyHistoryItem)
    } else {
      alternate(pasteHistoryItem)
      prependHistoryItems(copyHistoryItem, pasteHistoryItem)
    }

    if historyItems.count > (UserDefaults.standard.size * 2) {
      removeLastHistoryItem()
    }
  }

  func clear() {
    historyItems.forEach({ item in
      if items.contains(item) {
        removeItem(item)
      }
    })
    historyItems.removeAll()
  }

  func updateFilter(filter: String) {
    let results = search.search(string: filter, within: historyItems)

    // First, remove items that don't match search.
    for item in historyItems {
      if items.contains(item) && !results.contains(item) {
        removeItem(item)
      }
    }

    // Second, update order of items to match search results order.
    results.reversed().forEach({ item in
      if items.contains(item) {
        removeItem(item)
      }
      insertItem(item, at: 1)
    })

    setKeyEquivalents(results)
    highlight(results.first)
  }

  func select() {
    if let item = highlightedItem {
      performActionForItem(at: index(of: item))
      cancelTracking()
    }
  }

  func selectPrevious(alt: Bool) {
    if !highlightNext(items.reversed(), alt: alt) {
      selectLast(alt: alt) // start from the end after reaching the first item
    }
  }

  func selectNext(alt: Bool) {
    if !highlightNext(items, alt: alt) {
      selectFirst(alt: alt) // start from the beginning after reaching the last item
    }
  }

  func selectFirst(alt: Bool = false) {
    highlight(highlightableItems(items, alt: alt).first)
  }

  func selectLast(alt: Bool = false) {
    highlight(highlightableItems(items, alt: alt).last)
  }

  func delete() {
    guard let itemToRemove = highlightedItem else {
      return
    }

    if let historyItemToRemove = itemToRemove as? HistoryMenuItem {
      if let fullTitle = historyItemToRemove.fullTitle {
        historyItems.removeAll(where: { $0.fullTitle == fullTitle })

        let historyItemToRemoveIndex = index(of: historyItemToRemove)
        removeItem(at: historyItemToRemoveIndex) // main item
        removeItem(at: historyItemToRemoveIndex - 1) // alt item

        history?.remove(fullTitle)

        setKeyEquivalents(historyItems)
        highlight(items[historyItemToRemoveIndex])
      }
    }
  }

  private func highlightNext(_ items: [NSMenuItem], alt: Bool) -> Bool {
    let highlightableItems = self.highlightableItems(items, alt: alt)
    let currentHighlightedItem = highlightedItem ?? highlightableItems.first
    var itemsIterator = highlightableItems.makeIterator()
    while let item = itemsIterator.next() {
      if item == currentHighlightedItem {
        if let itemToHighlight = itemsIterator.next() {
          highlight(itemToHighlight)
          return true
        }
      }
    }
    return false
  }

  private func highlightableItems(_ items: [NSMenuItem], alt: Bool = false) -> [NSMenuItem] {
    return items.filter { !$0.isSeparatorItem && $0.isEnabled && $0.isAlternate == alt }
  }

  private func highlight(_ itemToHighlight: NSMenuItem?) {
    let highlightItemSelector = NSSelectorFromString("highlightItem:")
    // we need to highlight filter menu item to force menu redrawing
    // when it has more items that can fit into the screen height
    // and scrolling items are added to the top and bottom of menu
    perform(highlightItemSelector, with: items.first)
    if let item = itemToHighlight {
      if items.contains(item) {
        perform(highlightItemSelector, with: item)
      }
    }
  }

  private func setKeyEquivalents(_ items: [NSMenuItem]) {
    // First, clear all existing key equivalents.
    for item in historyItems {
      item.keyEquivalent = ""
    }

    // Second, add key eqvuivalents up to max.
    // Both main and alternate item should have the same key equivalent.
    var hotKey = 1
    for item in items where hotKey <= maxHotKey {
      item.keyEquivalent = String(hotKey)
      if item.isAlternate {
        hotKey += 1
      }
    }
  }

  private func prependHistoryItems(_ firstItem: HistoryMenuItem, _ secondItem: HistoryMenuItem) {
    historyItems.insert(contentsOf: [firstItem, secondItem], at: 0)
    insertItem(secondItem, at: 1)
    insertItem(firstItem, at: 1)
  }

  private func removeDuplicateItems(_ entry: String) {
    historyItems.removeAll(where: { $0.fullTitle == entry })
    items.forEach({ item in
      if let historyItem = item as? HistoryMenuItem {
        if historyItem.fullTitle == entry {
          removeItem(item)
        }
      }
    })
  }

  private func removeLastHistoryItem() {
    let altItem = historyItems.removeLast()
    let mainItem = historyItems.removeLast()
    removeItem(altItem)
    removeItem(mainItem)
  }

  private func alternate(_ item: HistoryMenuItem) {
    item.keyEquivalentModifierMask = [.option]
    item.isHidden = true
    item.isAlternate = true
  }

  private func copy(_ item: HistoryMenuItem) {
    if let title = item.fullTitle {
      clipboard.copy(title)
    }
  }

  private func copyAndPaste(_ item: HistoryMenuItem) {
    copy(item)
    clipboard.paste()
  }
}
