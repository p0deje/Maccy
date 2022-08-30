// swiftlint:disable file_length
import AppKit

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
// swiftlint:disable type_body_length
class Menu: NSMenu, NSMenuDelegate {
  static let menuWidth = 300

  class IndexedItem: NSObject {
    var value: String
    var title: String { item.title }
    var item: HistoryItem!
    var menuItems: [HistoryMenuItem]

    init(value: String, item: HistoryItem?, menuItems: [HistoryMenuItem]) {
      self.value = value
      self.item = item
      self.menuItems = menuItems
    }
  }

  public let maxHotKey = 9

  public var firstUnpinnedHistoryMenuItem: HistoryMenuItem? {
    historyMenuItems.first(where: { !$0.isPinned })
  }
  public var lastUnpinnedHistoryMenuItem: HistoryMenuItem? {
    historyMenuItems.last(where: { !$0.isPinned })
  }

  internal var historyMenuItems: [HistoryMenuItem] {
    items.compactMap({ $0 as? HistoryMenuItem })
  }

  private let search = Search()

  private let historyMenuItemOffset = 1 // The first item is reserved for header.
  private let historyMenuItemsGroup = 3 // 1 main and 2 alternates

  private var clipboard: Clipboard!
  private var history: History!

  private var indexedItems: [IndexedItem] = []

  // When menu opens, we don't know which of the alternate menu items
  // is actually visible. We would like to highlight the one that is currently
  // visible and it seems like the only way to do is to try to find out
  // which ones has keyEquivalentModifierMask matching currently pressed
  // modifier flags.
  private var firstVisibleUnpinnedHistoryMenuItem: HistoryMenuItem? {
    let firstPinnedMenuItems = historyMenuItems.filter({ !$0.isPinned }).prefix(historyMenuItemsGroup)
    return firstPinnedMenuItems.first(where: { NSEvent.modifierFlags == $0.keyEquivalentModifierMask }) ??
      firstPinnedMenuItems.first(where: { NSEvent.modifierFlags.isSuperset(of: $0.keyEquivalentModifierMask) }) ??
      firstPinnedMenuItems.first
  }

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
    self.minimumWidth = CGFloat(Menu.menuWidth)
  }

  func menuWillOpen(_ menu: NSMenu) {
    updateUnpinnedItemsVisibility()
    setKeyEquivalents(historyMenuItems)
    highlight(firstVisibleUnpinnedHistoryMenuItem ?? historyMenuItems.first)
  }

  func buildItems() {
    clearAll()

    for item in history.all {
      let menuItems = buildMenuItems(item)
      if let menuItem = menuItems.first {
        indexedItems.append(IndexedItem(value: menuItem.value,
                                        item: item,
                                        menuItems: menuItems))
        menuItems.forEach(addItem(_:))
      }
    }
  }

  func add(_ item: HistoryItem) {
    let sortedItems = history.all
    guard let insertionIndex = sortedItems.firstIndex(where: { $0 == item }) else {
      return
    }

    let menuItems = buildMenuItems(item)
    guard let menuItem = menuItems.first else {
      return
    }
    indexedItems.insert(IndexedItem(value: menuItem.value,
                                    item: item,
                                    menuItems: menuItems),
                        at: insertionIndex)

    var menuItemInsertionIndex = insertionIndex
    // Keep pins on the same place.
    if item.pin != nil {
      if let index = historyMenuItems.firstIndex(where: { item.supersedes($0.item) }) {
        menuItemInsertionIndex = index
      }
    } else {
      menuItemInsertionIndex *= historyMenuItemsGroup
    }

    if menuItemInsertionIndex <= historyMenuItems.count {
      menuItemInsertionIndex += historyMenuItemOffset
      for menuItem in menuItems.reversed() {
        insertItem(menuItem, at: menuItemInsertionIndex)
      }
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

    // Get all the items that match results.
    let foundItems = results.map({ $0.object })

    // Ensure that pinned items are visible after search is cleared.
    if filter.isEmpty {
      results.append(contentsOf: indexedItems.filter({ $0.item.pin != nil })
                                             .map({ Search.SearchResult(score: nil, object: $0, titleMatches: []) }))
    }

    // First, remove items that don't match search.
    for indexedItem in indexedItems {
      if !foundItems.contains(indexedItem) {
        for menuItem in indexedItem.menuItems where items.contains(menuItem) {
          removeItem(menuItem)
        }
      }
    }

    // Second, update order of items to match search results order.
    for result in results.reversed() {
      for menuItem in result.object.menuItems.reversed() {
        if items.contains(menuItem) {
          removeItem(menuItem)
        }
        menuItem.highlight(result.titleMatches)
        insertItem(menuItem, at: historyMenuItemOffset)
      }
    }

    setKeyEquivalents(historyMenuItems)
    highlight(filter.isEmpty ? firstUnpinnedHistoryMenuItem : historyMenuItems.first)
  }

  func select(_ searchQuery: String) {
    if let item = highlightedItem {
      performActionForItem(at: index(of: item))
      cancelTrackingWithoutAnimation()
    } else if !searchQuery.isEmpty && historyMenuItems.isEmpty {
      clipboard.copy(searchQuery)
      updateFilter(filter: searchQuery)
      select(searchQuery)
    }
  }

  func select(position: Int) -> String? {
    guard indexedItems.count > position,
          let item = indexedItems[position].menuItems.first else {
      return nil
    }

    performActionForItem(at: index(of: item))
    return indexedItems[position].value
  }

  func selectPrevious() {
    if !highlightNext(items.reversed()) {
      highlight(highlightableItems(items).last) // start from the end after reaching the first item
    }
  }

  func selectNext() {
    if !highlightNext(items) {
      highlight(highlightableItems(items).first) // start from the beginning after reaching the last item
    }
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

      updateUnpinnedItemsVisibility()
      setKeyEquivalents(historyMenuItems)
      highlight(items[historyItemToRemoveIndex])
    }
  }

  func pinOrUnpin() -> Bool {
    guard let altItemToPin = highlightedItem as? HistoryMenuItem else {
      return false
    }

    guard let historyItem = indexedItems.first(where: { $0.item == altItemToPin.item }) else {
      return false
    }

    if altItemToPin.isPinned {
      for menuItem in historyItem.menuItems {
        menuItem.unpin()
        removeItem(menuItem)
      }
    } else {
      let pin = HistoryItem.randomAvailablePin
      for menuItem in historyItem.menuItems {
        menuItem.pin(pin)
        removeItem(menuItem)
      }
    }

    history.update(altItemToPin.item)

    let sortedItems = history.all
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

    return true
  }

  func resizeImageMenuItems() {
    historyMenuItems.forEach {
      $0.resizeImage()
    }
  }

  private func highlightNext(_ items: [NSMenuItem]) -> Bool {
    let highlightableItems = self.highlightableItems(items)
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

  private func highlightableItems(_ items: [NSMenuItem]) -> [NSMenuItem] {
    return items.filter { !$0.isSeparatorItem && $0.isEnabled && !$0.isHidden }
  }

  private func highlight(_ itemToHighlight: NSMenuItem?) {
    let highlightItemSelector = NSSelectorFromString("highlightItem:")
    if let item = itemToHighlight {
      // we need to highlight filter menu item to force menu redrawing
      // when it has more items that can fit into the screen height
      // and scrolling items are added to the top and bottom of menu
      perform(highlightItemSelector, with: items.first)
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
        if let lastItem = lastUnpinnedHistoryMenuItem {
          insertItem(historyItem, at: index(of: lastItem) + 1)
        }
      }
      if maxVisibleItems == limit {
        break
      }
    }
  }

  private func showAllUnpinnedItems() {
    for historyItem in indexedItems.flatMap({ $0.menuItems }).filter({ !$0.isPinned }) {
      if !historyMenuItems.contains(historyItem) {
        insertItem(historyItem, at: historyMenuItems.count + historyMenuItemOffset)
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
// swiftlint:enable file_length
