import AppKit

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
class Menu: NSMenu, NSMenuDelegate {
  public let maxHotKey = 9
  public let menuWidth = 300

  private let search = Search()
  private let availablePins = Set([
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
    "m", "n", "o", "r", "s", "t", "u", "v", "w", "x", "y", "z"
  ])

  private var clipboard: Clipboard!
  private var history: History!
  private var historyItems: [HistoryMenuItem] = []

  required init(coder decoder: NSCoder) {
    super.init(coder: decoder)
  }

  init(history: History, clipboard: Clipboard) {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.maxMenuItems: UserDefaults.Values.maxMenuItems])
    super.init(title: "Maccy")
    self.history = history
    self.clipboard = clipboard
    self.delegate = self
    self.minimumWidth = CGFloat(menuWidth)
  }

  func menuWillOpen(_ menu: NSMenu) {
    buildItems(history.all)
    setKeyEquivalents(historyItems)
    highlight(historyItems.first(where: { !$0.isPinned }))
  }

  func buildItems(_ allItems: [HistoryItem]) {
    clearAll()
    for item in Sorter(by: UserDefaults.standard.sortBy).sort(allItems) {
      let copyHistoryItem = HistoryMenuItem(item: item, onSelected: copy(_:))
      let pasteHistoryItem = HistoryMenuItem(item: item, onSelected: copyAndPaste(_:))

      if UserDefaults.standard.pasteByDefault {
        alternate(copyHistoryItem)
        prependHistoryItems(pasteHistoryItem, copyHistoryItem)
      } else {
        alternate(pasteHistoryItem)
        prependHistoryItems(copyHistoryItem, pasteHistoryItem)
      }
    }
    
    for historyItem in historyItems.reversed() {
        if items.count > UserDefaults.standard.maxMenuItems * 2 + 7 {
            removeItem(historyItem)
        }
    }
  }

  func clearAll() {
    clear(historyItems)
  }

  func clearUnpinned() {
    clear(historyItems.filter({ !$0.isPinned }))
  }

  func updateFilter(filter: String) {
    let results = Array(search.search(string: filter, within: historyItems).prefix(UserDefaults.standard.maxMenuItems * 2))

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
      historyItems.removeAll(where: { $0 == historyItemToRemove })
      history.remove(historyItemToRemove.item)

      let historyItemToRemoveIndex = index(of: historyItemToRemove)
      removeItem(at: historyItemToRemoveIndex) // main item
      removeItem(at: historyItemToRemoveIndex - 1) // alt item

      setKeyEquivalents(historyItems)
      highlight(items[historyItemToRemoveIndex])
    }
  }

  func pinOrUnpin() {
    guard let altItemToPin = highlightedItem as? HistoryMenuItem else {
      return
    }

    let altItemToPinIndex = index(of: altItemToPin)
    if let mainItemToPin = item(at: altItemToPinIndex - 1) as? HistoryMenuItem {
      if altItemToPin.isPinned {
        mainItemToPin.unpin()
        altItemToPin.unpin()
      } else {
        let pin = randomAvailablePin()
        mainItemToPin.pin(pin)
        altItemToPin.pin(pin)
      }
    }

    history.update(altItemToPin.item)
    buildItems(history.all)
    setKeyEquivalents(historyItems)
    highlight(historyItems.first(where: { $0.item == altItemToPin.item }))
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

  private func setKeyEquivalents(_ items: [HistoryMenuItem]) {
    // First, clear all existing key equivalents.
    for item in historyItems where !item.isPinned {
      item.keyEquivalent = ""
    }

    // Second, add key eqvuivalents up to max.
    // Both main and alternate item should have the same key equivalent.
    var hotKey = 1
    for item in items where hotKey <= maxHotKey && !item.isPinned {
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

  private func randomAvailablePin() -> String {
    let assignedPins = Set(historyItems.map({ $0.keyEquivalent }))
    return availablePins.subtracting(assignedPins).randomElement() ?? ""
  }

  private func copy(_ item: HistoryMenuItem) {
    clipboard.copy(item.item)
  }

  private func copyAndPaste(_ item: HistoryMenuItem) {
    copy(item)
    clipboard.paste()
  }

  private func clear(_ itemsToClear: [HistoryMenuItem]) {
    itemsToClear.forEach({ item in
      if items.contains(item) {
        removeItem(item)
      }

      historyItems.removeAll(where: { $0 == item})
    })
  }
}
