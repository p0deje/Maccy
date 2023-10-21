// swiftlint:disable file_length
import AppKit

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
// swiftlint:disable type_body_length
class Menu: NSMenu, NSMenuDelegate {
  static let menuWidth = 300

  public let maxHotKey = 9

  public var isVisible: Bool = false

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

  private let previewController = PreviewPopoverController()

  private let historyMenuItemOffset = 1 // The first item is reserved for header.
  private let historyMenuItemsGroup = 3 // 1 main and 2 alternates
  private var previewMenuItemOffset = 0

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

  private var maxMenuItems: Int {
    let count = UserDefaults.standard.maxMenuItems
    return count > 0 ? count : Int.max;
  }
  private var maxVisibleItems: Int {
    let count = UserDefaults.standard.maxMenuItems
    return count > 0 ? count * historyMenuItemsGroup : Int.max
  }
  private var lastMenuLocation: PopupLocation?
  private var menuHeader: MenuHeaderView? { items.first?.view as? MenuHeaderView }
  private var menuWindow: NSWindow? { NSApp.menuWindow }

  required init(coder decoder: NSCoder) {
    super.init(coder: decoder)
  }

  init(history: History, clipboard: Clipboard) {
    super.init(title: "Maccy")

    self.history = history
    self.clipboard = clipboard
    self.delegate = self
    self.minimumWidth = CGFloat(Menu.menuWidth)

    if #unavailable(macOS 14) {
      self.previewMenuItemOffset = 1
    }
  }

  func popUpMenu(at location: NSPoint, ofType locationType: PopupLocation) {
    prepareForPopup(location: locationType)
    super.popUp(positioning: nil, at: location, in: nil)
  }

  func prepareForPopup(location: PopupLocation) {
    lastMenuLocation = location
    updateUnpinnedItemsVisibility()
    setKeyEquivalents(historyMenuItems)
  }

  func menuWillOpen(_ menu: NSMenu) {
    isVisible = true
    previewController.menuWillOpen()
    highlight(firstVisibleUnpinnedHistoryMenuItem ?? historyMenuItems.first)
  }

  internal func adjustMenuWindowPosition() {
    guard let location = lastMenuLocation else {
      return
    }
    if let point = location.location(for: self.size) {
      menuWindow?.setFrameTopLeftPoint(point)
    }
  }

  func menuDidClose(_ menu: NSMenu) {
    isVisible = false
    lastMenuLocation = nil
    previewController.menuDidClose()
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    previewController.cancelPopover()
    guard let item = item as? HistoryMenuItem else {
      return
    }
    previewController.showPopover(for: item, allItems: indexedItems)
  }

  func buildItems() {
    clearAll()

    for item in history.all {
      let indexedItem = IndexedItem(
        item: item,
        clipboard: clipboard
      )
      indexedItems.append(indexedItem)
      addIndexedItem(indexedItem)
    }
  }

  func add(_ item: HistoryItem) {
    let sortedItems = history.all
    guard let insertionIndex = sortedItems.firstIndex(where: { $0 == item }) else {
      return
    }

    let indexedItem = IndexedItem(
      item: item,
      clipboard: clipboard
    )
    indexedItems.insert(indexedItem, at: insertionIndex)

    ensureInEventTrackingModeIfVisible {
      var menuItemInsertionIndex = insertionIndex
      // Keep pins on the same place.
      if item.pin != nil {
        if let index = self.historyMenuItems.firstIndex(where: { item.supersedes($0.item) }) {
          menuItemInsertionIndex = (index + self.previewMenuItemOffset)
        }
      } else {
        menuItemInsertionIndex *= (self.historyMenuItemsGroup + self.previewMenuItemOffset)
      }
      menuItemInsertionIndex += self.historyMenuItemOffset
      self.insertIndexedItem(indexedItem, at: menuItemInsertionIndex)
      self.clearRemovedItems()
    }
  }

  func clearAll() {
    clear(indexedItems)
  }

  func clearUnpinned() {
    clear(indexedItems.filter({ $0.item.pin == nil }))
  }

  func updateFilter(filter: String) {
    let window = menuWindow
    var savedTopLeft = window?.frame.origin ?? NSPoint()
    savedTopLeft.y += window?.frame.height ?? 0.0

    var results = search.search(string: filter, within: indexedItems)

    // Strip the results that are longer than visible items.
    if maxMenuItems < results.count {
      results = Array(results[0...maxMenuItems - 1])
    }

    // Get all the items that match results.
    let foundItems = results.map({ $0.object })

    // Ensure that pinned items are visible after search is cleared.
    if filter.isEmpty {
      results.append(
        contentsOf: indexedItems
          .filter({ $0.item.pin != nil })
          .map({ Search.SearchResult(score: nil, object: $0, titleMatches: []) })
      )
    }

    // First, remove items that don't match search.
    for indexedItem in indexedItems {
      if !foundItems.contains(indexedItem) {
        removeIndexedItem(indexedItem)
      }
    }

    // Second, update order of items to match search results order.
    for result in results.reversed() {
      removeIndexedItem(result.object)
      insertIndexedItem(result.object, at: historyMenuItemOffset)
      for menuItem in result.object.menuItems {
        menuItem.highlight(result.titleMatches)
      }
    }

    setKeyEquivalents(historyMenuItems)
    highlight(filter.isEmpty ? firstUnpinnedHistoryMenuItem : historyMenuItems.first)

    ensureInEventTrackingModeIfVisible(dispatchLater: true) {
      let window = self.menuWindow
      window?.setFrameTopLeftPoint(savedTopLeft)
    }
  }

  func select(_ searchQuery: String) {
    if let item = highlightedItem {
      performActionForItem(at: index(of: item))
    } else if !searchQuery.isEmpty && historyMenuItems.isEmpty {
      clipboard.copy(searchQuery)
      updateFilter(filter: searchQuery)
    }
    cancelTrackingWithoutAnimation()
  }

  func select(position: Int) -> String? {
    guard indexedItems.count > position,
          let item = indexedItems[position].menuItems.first else {
      return nil
    }

    performActionForItem(at: index(of: item))
    return indexedItems[position].title
  }

  func historyItem(at position: Int) -> HistoryItem? {
    guard indexedItems.indices.contains(position) else {
      return nil
    }

    return indexedItems[position].item
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

      // When deleting mulitple items by holding the removal keys
      // we sometimes get into a race condition with menu updating indices.
      // https://github.com/p0deje/Maccy/issues/628
      guard historyItemToRemoveIndex != -1 else { return }

      if let indexedItem = indexedItems.first(where: { $0.item == historyItemToRemove.item }) {
        removeIndexedItem(indexedItem)
        if let removeIndex = indexedItems.firstIndex(of: indexedItem) {
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
      removeIndexedItem(historyItem)
      for menuItem in historyItem.menuItems {
        menuItem.unpin()
      }
    } else {
      let pin = HistoryItem.randomAvailablePin
      removeIndexedItem(historyItem)
      for menuItem in historyItem.menuItems {
        menuItem.pin(pin)
      }
    }

    history.update(altItemToPin.item)

    let sortedItems = history.all
    if let newIndex = sortedItems.firstIndex(of: altItemToPin.item) {
      if let removeIndex = indexedItems.firstIndex(of: historyItem) {
        indexedItems.remove(at: removeIndex)
        indexedItems.insert(historyItem, at: newIndex)
      }

      let menuItemIndex = newIndex * (historyMenuItemsGroup + previewMenuItemOffset) + historyMenuItemOffset
      insertIndexedItem(historyItem, at: menuItemIndex)

      updateFilter(filter: "") // show all items
      highlight(historyItem.menuItems[1])
    }

    return true
  }

  func resizeImageMenuItems() {
    historyMenuItems.forEach {
      $0.resizeImage()
    }
  }

  func regenerateMenuItemTitles() {
    historyMenuItems.forEach {
      $0.regenerateTitle()
    }
    update()
  }

  func updateUnpinnedItemsVisibility() {
    let historyMenuItemsCount = historyMenuItems.filter({ !$0.isPinned }).count

    if maxVisibleItems <= historyMenuItemsCount {
      hideUnpinnedItemsOverLimit(currentCount: historyMenuItemsCount)
    } else {
      appendUnpinnedItemsUntilLimit(currentCount: historyMenuItemsCount)
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
    if #available(macOS 14, *) {
      DispatchQueue.main.async { self.highlightItem(itemToHighlight) }
    } else {
      highlightItem(itemToHighlight)
    }
  }

  private func highlightItem(_ itemToHighlight: NSMenuItem?) {
    let highlightItemSelector = NSSelectorFromString("highlightItem:")
    // we need to highlight filter menu item to force menu redrawing
    // when it has more items that can fit into the screen height
    // and scrolling items are added to the top and bottom of menu
    perform(highlightItemSelector, with: items.first)
    if let item = itemToHighlight, !item.isHighlighted, items.contains(item) {
      perform(highlightItemSelector, with: item)
    } else {
      // Unhighlight current item.
      perform(highlightItemSelector, with: nil)
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

  private func clear(_ itemsToClear: [IndexedItem]) {
    for indexedItem in itemsToClear {
      removeIndexedItem(indexedItem)

      if let removeIndex = indexedItems.firstIndex(of: indexedItem) {
        indexedItems.remove(at: removeIndex)
      }
    }
  }

  private func hideUnpinnedItemsOverLimit(currentCount: Int) {
    var currentCount = currentCount
    for indexedItem in indexedItems.filter({ $0.item.pin == nil }).reversed() {
      removeIndexedItem(indexedItem)
      currentCount -= indexedItem.menuItemCount

      if maxVisibleItems >= currentCount {
        return
      }
    }
  }

  private func appendUnpinnedItemsUntilLimit(currentCount: Int) {
    var currentCount = currentCount
    for indexedItem in indexedItems.filter({ $0.item.pin == nil }) {
      if let lastItem = lastUnpinnedHistoryMenuItem {
        let index = index(of: lastItem) + 1 + previewMenuItemOffset
        insertIndexedItem(indexedItem, at: index)
        currentCount += indexedItem.menuItemCount
      }

      if maxVisibleItems <= currentCount {
        return
      }
    }
  }

  private func chunks(_ items: [HistoryMenuItem]) -> [[HistoryMenuItem]] {
    return stride(from: 0, to: items.count, by: historyMenuItemsGroup).map({ index in
      Array(items[index ..< Swift.min(index + historyMenuItemsGroup, items.count)])
    })
  }

  private func clearRemovedItems() {
    let currentHistoryItems = history.all
    for indexedItem in indexedItems where !currentHistoryItems.contains(indexedItem.item) {
      removeIndexedItem(indexedItem)

      if let removeIndex = indexedItems.firstIndex(of: indexedItem) {
        indexedItems.remove(at: removeIndex)
      }
    }
  }

  private func addIndexedItem(_ item: IndexedItem) {
    item.menuItems.forEach(safeAddItem(_:))
    if #unavailable(macOS 14), let popoverAnchor = item.popoverAnchor {
      safeAddItem(popoverAnchor)
    }
  }

  private func insertIndexedItem(_ item: IndexedItem, at index: Int) {
    if #unavailable(macOS 14), let popoverAnchor = item.popoverAnchor {
      safeInsertItem(popoverAnchor, at: index)
    }

    for menuItem in item.menuItems.reversed() {
      safeInsertItem(menuItem, at: index)
    }
  }

  private func removeIndexedItem(_ item: IndexedItem?) {
    guard let item = item else { return }
    if #unavailable(macOS 14) {
      safeRemoveItem(item.popoverAnchor)
    }
    item.menuItems.forEach(safeRemoveItem(_:))
  }

  private func safeAddItem(_ item: NSMenuItem) {
    guard !items.contains(item) else {
      return
    }

    addItem(item)
  }

  private func safeInsertItem(_ item: NSMenuItem, at index: Int) {
    guard !items.contains(item), index <= items.count else {
      return
    }

    insertItem(item, at: index)
  }

  private func safeRemoveItem(_ item: NSMenuItem?) {
    guard let item = item,
          items.contains(item) else {
      return
    }

    removeItem(item)
  }

  private func ensureInEventTrackingModeIfVisible(
    dispatchLater: Bool = false,
    block: @escaping () -> Void
  ) {
    if isVisible && (
      dispatchLater ||
      RunLoop.current != RunLoop.main ||
      RunLoop.current.currentMode != .eventTracking
    ) {
      RunLoop.main.perform(inModes: [.eventTracking], block: block)
    } else {
      block()
    }
  }
}
// swiftlint:enable type_body_length
// swiftlint:enable file_length
