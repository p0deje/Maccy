import AppKit

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
// swiftlint:disable type_body_length
class Menu: NSMenu, NSMenuDelegate {
  class IndexedItem: NSObject {
    var value: String
    var item: HistoryItem!
    var menuItems: [HistoryMenuItem]

    init(value: String, item: HistoryItem?, menuItems: [HistoryMenuItem]) {
      self.value = value
      self.item = item
      self.menuItems = menuItems
    }
  }

  public let maxHotKey = 9
  public let menuWidth = 300

  public var firstUnpinnedHistoryMenuItem: HistoryMenuItem? {
    historyMenuItems.first(where: { !$0.isPinned })
  }

  internal var historyMenuItems: [HistoryMenuItem] {
    items.compactMap({ $0 as? HistoryMenuItem })
  }

  private let search = Search()
  private let availablePins = Set([
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
    "m", "n", "o", "r", "s", "t", "u", "v", "w", "x", "y", "z"
  ])

  private let historyMenuItemOffset = 1 // The first item is reserved for header.
  private let historyMenuItemsGroup = 3 // 1 main and 2 alternates

  private var clipboard: Clipboard!
  private var history: History!

  private var indexedItems: [IndexedItem] = []

  private var maxMenuItems: Int { UserDefaults.standard.maxMenuItems }
  private var maxVisibleItems: Int { maxMenuItems * historyMenuItemsGroup }

  required init(coder decoder: NSCoder) {
    super.init(coder: decoder)
  }

  init(history: History, clipboard: Clipboard) {
    UserDefaults.standard.register(defaults: [
      UserDefaults.Keys.maxMenuItems: UserDefaults.Values.maxMenuItems
    ])

    super.init(title: "Maccy")

    self.history = history
    self.clipboard = clipboard
    self.delegate = self
    self.minimumWidth = CGFloat(menuWidth)
  }

  func menuWillOpen(_ menu: NSMenu) {
    updateUnpinnedItemsVisibility()
    setKeyEquivalents(historyMenuItems)
    highlight(firstUnpinnedHistoryMenuItem)
  }

  func buildItems() {
    clearAll()

    for item in Sorter(by: UserDefaults.standard.sortBy).sort(history.all) {
      let menuItems = buildMenuItems(item)
      if let value = menuItems.first?.value {
        indexedItems.append(IndexedItem(value: value, item: item, menuItems: menuItems))
        for menuItem in menuItems {
          addItem(menuItem)
        }
      }
    }
  }

  func add(_ item: HistoryItem) {
    guard item.pin == nil else {
      return
    }

    let sortedItems = Sorter(by: UserDefaults.standard.sortBy).sort(history.all)
    guard let insertionIndex = sortedItems.firstIndex(where: { $0 == item }) else {
      return
    }

    let menuItems = buildMenuItems(item)
    guard let value = menuItems.first?.value else {
      return
    }

    indexedItems.insert(IndexedItem(value: value, item: item, menuItems: menuItems), at: insertionIndex)
    for menuItem in menuItems.reversed() {
      insertItem(menuItem, at: insertionIndex * historyMenuItemsGroup + historyMenuItemOffset)
    }

    clearRemovedItems()
  }

  func clearAll() {
    clear(indexedItems.flatMap({ $0.menuItems }))
  }

  func clearUnpinned() {
    clear(indexedItems.flatMap({ $0.menuItems }).filter({ !$0.isPinned }))
  }

  func updateFilter(filter: String) {
    var results = search.search(string: filter, within: indexedItems)

    // Strip the results that are longer than visible items.
    if maxMenuItems > 0 && maxMenuItems < results.count {
      results = Array(results[0...maxMenuItems - 1])
    }

    // Get all the menu items that match results.
    var foundMenuItems = results.flatMap({ $0.menuItems })
    if filter.isEmpty {
      foundMenuItems.append(contentsOf: indexedItems.flatMap({ $0.menuItems }).filter({ $0.isPinned }))
    }

    // First, remove items that don't match search.
    for indexedItem in indexedItems {
      if !results.contains(indexedItem) {
        for menuItem in indexedItem.menuItems where items.contains(menuItem) {
          removeItem(menuItem)
        }
      }
    }

    // Second, update order of items to match search results order.
    for menuItem in foundMenuItems.reversed() {
      if items.contains(menuItem) {
        removeItem(menuItem)
      }
      insertItem(menuItem, at: historyMenuItemOffset)
    }

    setKeyEquivalents(historyMenuItems)
    highlight(historyMenuItems.first)
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
      let historyItemToRemoveIndex = index(of: historyItemToRemove)

      if let historyItem = indexedItems.first(where: { $0.item == historyItemToRemove.item }) {
        historyItem.menuItems.forEach(removeItem(_:))
        if let removeIndex = indexedItems.firstIndex(of: historyItem) {
          indexedItems.remove(at: removeIndex)
        }
      }

      history.remove(historyItemToRemove.item)

      setKeyEquivalents(historyMenuItems)
      highlight(items[historyItemToRemoveIndex])
    }
  }

  func pinOrUnpin() {
    guard let altItemToPin = highlightedItem as? HistoryMenuItem else {
      return
    }

    guard let historyItem = indexedItems.first(where: { $0.item == altItemToPin.item }) else {
      return
    }

    if altItemToPin.isPinned {
      for menuItem in historyItem.menuItems {
        menuItem.unpin()
        removeItem(menuItem)
      }
    } else {
      let pin = randomAvailablePin()
      for menuItem in historyItem.menuItems {
        menuItem.pin(pin)
        removeItem(menuItem)
      }
    }

    history.update(altItemToPin.item)

    let sortedItems = Sorter(by: UserDefaults.standard.sortBy).sort(history.all)
    if let newIndex = sortedItems.firstIndex(where: { $0 == altItemToPin.item }) {
      if let removeIndex = indexedItems.firstIndex(of: historyItem) {
        indexedItems.remove(at: removeIndex)
        indexedItems.insert(historyItem, at: newIndex)
      }

      let menuItemIndex = newIndex * historyMenuItemsGroup + historyMenuItemOffset
      // Ensure that it's possible to insert at the specified item.
      // This won't be possible when unpinning item that should be inserted
      // at index higher than maxVisibleItems.
      if menuItemIndex <= items.count {
        for menuItem in historyItem.menuItems.reversed() {
          insertItem(menuItem, at: menuItemIndex)
        }
      }

      updateFilter(filter: "") // show all items
      highlight(historyItem.menuItems.first)
    }
  }

  func resizeImageMenuItems() {
    historyMenuItems.forEach {
      $0.resizeImage()
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

  private func setKeyEquivalents(_ items: [HistoryMenuItem]) {
    // First, clear all existing key equivalents.
    for item in historyMenuItems where !item.isPinned {
      item.keyEquivalent = ""
    }

    // Second, add key equivalents up to max.
    // Both main and alternate item should have the same key equivalent.
    let unpinnedItems = items.filter({ !$0.isPinned })
    var hotKey = 1
    for chunk in chunks(unpinnedItems) where hotKey <= maxHotKey {
      for item in chunk {
        item.keyEquivalent = String(hotKey)
      }
      hotKey += 1
    }
  }

  private func randomAvailablePin() -> String {
    let assignedPins = Set(historyMenuItems.map({ $0.keyEquivalent }))
    return availablePins.subtracting(assignedPins).randomElement() ?? ""
  }

  private func clear(_ itemsToClear: [HistoryMenuItem]) {
    itemsToClear.forEach({ menuItem in
      if items.contains(menuItem) {
        removeItem(menuItem)
      }

      if let removeIndex = indexedItems.firstIndex(where: { $0.item == menuItem.item }) {
        indexedItems.remove(at: removeIndex)
      }
    })
  }

  private func updateUnpinnedItemsVisibility() {
    let historyMenuItemsCount = historyMenuItems.filter({ !$0.isPinned }).count

    if maxVisibleItems > 0 {
      if maxVisibleItems <= historyMenuItemsCount {
        hideUnpinnedItemsOverLimit(historyMenuItemsCount)
      } else if maxVisibleItems > historyMenuItemsCount {
        appendUnpinnedItemsUntilLimit(historyMenuItemsCount)
      }
    } else {
      let allItemsCount = indexedItems.flatMap({ $0.menuItems }).filter({ !$0.isPinned }).count
      if historyMenuItemsCount < allItemsCount {
        showAllUnpinnedItems()
      }
    }
  }

  private func hideUnpinnedItemsOverLimit(_ limit: Int) {
    var limit = limit
    for historyItem in historyMenuItems.filter({ !$0.isPinned }).reversed() {
      if limit > maxVisibleItems {
        removeItem(historyItem)
        limit -= 1
      } else {
        break
      }
    }
  }

  private func appendUnpinnedItemsUntilLimit(_ limit: Int) {
    var limit = limit
    for historyItem in indexedItems.flatMap({ $0.menuItems }).filter({ !$0.isPinned }) {
      if !historyMenuItems.contains(historyItem) {
        limit += 1
        insertItem(historyItem, at: historyMenuItems.count)
      }
      if maxVisibleItems == limit {
        break
      }
    }
  }

  private func showAllUnpinnedItems() {
    for historyItem in indexedItems.flatMap({ $0.menuItems }).filter({ !$0.isPinned }) {
      if !historyMenuItems.contains(historyItem) {
        insertItem(historyItem, at: historyMenuItems.count)
      }
    }
  }

  private func buildMenuItems(_ item: HistoryItem) -> [HistoryMenuItem] {
    let menuItems = [
      HistoryMenuItem.CopyMenuItem(item: item, clipboard: clipboard),
      HistoryMenuItem.PasteMenuItem(item: item, clipboard: clipboard),
      HistoryMenuItem.PasteWithoutFormattingMenuItem(item: item, clipboard: clipboard)
    ]

    return menuItems.sorted(by: { !$0.isAlternate && $1.isAlternate })
  }

  private func chunks(_ items: [HistoryMenuItem]) -> [[HistoryMenuItem]] {
    return stride(from: 0, to: items.count, by: historyMenuItemsGroup).map({ index in
      Array(items[index ..< Swift.min(index + historyMenuItemsGroup, items.count)])
    })
  }

  private func clearRemovedItems() {
    let currentHistoryItems = history.all
    for indexedItem in indexedItems where !currentHistoryItems.contains(indexedItem.item) {
      for menuItem in indexedItem.menuItems where items.contains(menuItem) {
        removeItem(menuItem)
      }
      if let removeIndex = indexedItems.firstIndex(of: indexedItem) {
        indexedItems.remove(at: removeIndex)
      }
    }
  }
}
// swiftlint:enable type_body_length
