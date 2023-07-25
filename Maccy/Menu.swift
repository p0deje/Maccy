// swiftlint:disable file_length
import AppKit

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
// swiftlint:disable type_body_length
class Menu: NSMenu, NSMenuDelegate {
  static let menuWidth = 300
  static let popoverGap = 5.0

  class IndexedItem: NSObject {
    var value: String
    var title: String { item.title ?? "" }
    var item: HistoryItem!
    var menuItems: [HistoryMenuItem]
    lazy var previewMenuItem = HistoryMenuItem.PreviewMenuItem()

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

  private static let subsequentPreviewDelay = 0.2
  private var initialPreviewDelay: Double { Double(UserDefaults.standard.previewDelay) / 1000 }
  private lazy var previewThrottle = Throttler(minimumDelay: initialPreviewDelay)
  private var previewPopover: NSPopover?

  private let historyMenuItemOffset = 1 // The first item is reserved for header.
  private let historyMenuItemsGroup = 3 // 1 main and 2 alternates
  private let previewMenuItemOffset = 1 // 1 more item for the preview

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
    super.init(title: "Maccy")

    self.history = history
    self.clipboard = clipboard
    self.delegate = self
    self.minimumWidth = CGFloat(Menu.menuWidth)
  }

  func menuWillOpen(_ menu: NSMenu) {
    previewThrottle.minimumDelay = initialPreviewDelay

    updateUnpinnedItemsVisibility()
    setKeyEquivalents(historyMenuItems)
    highlight(firstVisibleUnpinnedHistoryMenuItem ?? historyMenuItems.first)
  }

  func menuDidClose(_ menu: NSMenu) {
    offloadCurrentPreview()
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    offloadCurrentPreview()

    guard let item = item as? HistoryMenuItem,
          let itemIndex = indexedItems.firstIndex(where: { $0.menuItems.contains(item) }) else {
      return
    }

    let indexedItem = indexedItems[itemIndex]

    if let previewMenuItemView = indexedItem.previewMenuItem.view,
       previewMenuItemView.frame.width != menu.size.width {
      previewMenuItemView.setFrameSize(
        NSSize(width: menu.size.width, height: previewMenuItemView.frame.height)
      )
    }

    previewThrottle.throttle { [self] in
      previewPopover = NSPopover()
      previewPopover?.animates = false
      previewPopover?.behavior = .semitransient
      previewPopover?.contentViewController = Preview(item: item.item)

      if let previewView = indexedItem.previewMenuItem.view,
         let previewWindow = previewView.window,
         let windowContentView = previewWindow.contentView {
        // Check if the preview item is non-obstructed (which can e.g. happen is scrollable and the scroll arrow overlaps the item)
        guard previewView.superview?.superview != nil else { return }

        previewThrottle.minimumDelay = Menu.subsequentPreviewDelay

        func getPrecedingView() -> NSView? {
          for index in (0..<itemIndex).reversed() {
            // PreviewMenuItem always has a view
            let view = indexedItems[index].previewMenuItem.view!
            // Check if preview item is visible (it may hidden by the saerch filter)
            if view.window != nil {
              return view
            }
          }
          // If the item is the first visible one, the preceding view is the header.
          guard let header = menu.items.first?.view as? MenuHeaderView? else {
            // Should never happen as we always have a MenuHeader installed.
            return nil
          }
          return header
        }

        guard let precedingView = getPrecedingView() else { return }

        let bottomPoint = previewView.convert(
          NSPoint(x: previewView.bounds.minX, y: previewView.bounds.maxY),
          to: windowContentView
        )
        let topPoint = precedingView.convert(
          NSPoint(x: previewView.bounds.minX, y: precedingView.bounds.minY),
          to: windowContentView
        )

        let heightOfVisibleMenuItem = abs(topPoint.y - bottomPoint.y)
        let boundsOfVisibleMenuItem = NSRect(origin: bottomPoint, size: NSSize(width: previewView.bounds.width, height: heightOfVisibleMenuItem))

        previewPopover?.show(
          relativeTo: boundsOfVisibleMenuItem,
          of: windowContentView,
          preferredEdge: .maxX
        )

        if let popoverWindow = previewPopover?.contentViewController?.view.window {
          if popoverWindow.frame.minX < previewWindow.frame.minX {
            popoverWindow.setFrameOrigin(NSPoint(x: popoverWindow.frame.minX - Menu.popoverGap, y: popoverWindow.frame.minY))
          } else {
            popoverWindow.setFrameOrigin(NSPoint(x: popoverWindow.frame.minX + Menu.popoverGap, y: popoverWindow.frame.minY))
          }
        }
      }
    }
  }

  func buildItems() {
    clearAll()

    for item in history.all {
      let menuItems = buildMenuItems(item)
      if let menuItem = menuItems.first {
        let indexedItem = IndexedItem(
          value: menuItem.value,
          item: item,
          menuItems: menuItems
        )
        indexedItems.append(indexedItem)
        menuItems.forEach(safeAddItem)
        safeAddItem(indexedItem.previewMenuItem)
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
    let indexedItem = IndexedItem(
      value: menuItem.value,
      item: item,
      menuItems: menuItems
    )
    indexedItems.insert(indexedItem, at: insertionIndex)

    var menuItemInsertionIndex = insertionIndex
    // Keep pins on the same place.
    if item.pin != nil {
      if let index = historyMenuItems.firstIndex(where: { item.supersedes($0.item) }) {
        menuItemInsertionIndex = (index + previewMenuItemOffset)
      }
    } else {
      menuItemInsertionIndex *= (historyMenuItemsGroup + previewMenuItemOffset)
    }

    menuItemInsertionIndex += historyMenuItemOffset
    safeInsertItem(indexedItem.previewMenuItem, at: menuItemInsertionIndex)
    for menuItem in menuItems.reversed() {
      safeInsertItem(menuItem, at: menuItemInsertionIndex)
    }

    clearRemovedItems()
  }

  func clearAll() {
    clear(indexedItems)
  }

  func clearUnpinned() {
    clear(indexedItems.filter({ $0.item.pin == nil }))
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
        indexedItem.menuItems.forEach(safeRemoveItem)
        safeRemoveItem(indexedItem.previewMenuItem)
      }
    }

    // Second, update order of items to match search results order.
    for result in results.reversed() {
      let previewItem = result.object.previewMenuItem
      safeRemoveItem(previewItem)
      safeInsertItem(previewItem, at: historyMenuItemOffset)

      for menuItem in result.object.menuItems.reversed() {
        safeRemoveItem(menuItem)
        menuItem.highlight(result.titleMatches)
        safeInsertItem(menuItem, at: historyMenuItemOffset)
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

      if let indexedItem = indexedItems.first(where: { $0.item == historyItemToRemove.item }) {
        safeRemoveItem(indexedItem.previewMenuItem)
        indexedItem.menuItems.forEach(safeRemoveItem)
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
      for menuItem in historyItem.menuItems {
        menuItem.unpin()
        safeRemoveItem(menuItem)
      }
      safeRemoveItem(historyItem.previewMenuItem)
    } else {
      let pin = HistoryItem.randomAvailablePin
      for menuItem in historyItem.menuItems {
        menuItem.pin(pin)
        safeRemoveItem(menuItem)
      }
      safeRemoveItem(historyItem.previewMenuItem)
    }

    history.update(altItemToPin.item)

    let sortedItems = history.all
    if let newIndex = sortedItems.firstIndex(of: altItemToPin.item) {
      if let removeIndex = indexedItems.firstIndex(of: historyItem) {
        indexedItems.remove(at: removeIndex)
        indexedItems.insert(historyItem, at: newIndex)
      }

      let menuItemIndex = newIndex * (historyMenuItemsGroup + previewMenuItemOffset) + historyMenuItemOffset
      safeInsertItem(historyItem.previewMenuItem, at: menuItemIndex)
      for menuItem in historyItem.menuItems.reversed() {
        safeInsertItem(menuItem, at: menuItemIndex)
      }

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

    if maxVisibleItems > 0 {
      if maxVisibleItems <= historyMenuItemsCount {
        hideUnpinnedItemsOverLimit(historyMenuItemsCount)
      } else if maxVisibleItems > historyMenuItemsCount {
        appendUnpinnedItemsUntilLimit(historyMenuItemsCount)
      }
    } else {
      let allItemsCount = indexedItems.flatMap({ $0.menuItems }).filter({ !$0.isPinned }).count
      if historyMenuItemsCount < allItemsCount {
        appendUnpinnedItemsUntilLimit(allItemsCount)
      }
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
      safeRemoveItem(indexedItem.previewMenuItem)
      indexedItem.menuItems.forEach(safeRemoveItem)

      if let removeIndex = indexedItems.firstIndex(of: indexedItem) {
        indexedItems.remove(at: removeIndex)
      }
    }
  }

  private func hideUnpinnedItemsOverLimit(_ limit: Int) {
    var limit = limit
    for indexedItem in indexedItems.filter({ $0.item.pin == nil }).reversed() {
      let menuItems = indexedItem.menuItems.filter({ historyMenuItems.contains($0) })
      if !menuItems.isEmpty {
        safeRemoveItem(indexedItem.previewMenuItem)
        menuItems.forEach { historyMenuItem in
          safeRemoveItem(historyMenuItem)
          limit -= 1
        }
      }

      if maxVisibleItems != 0 && maxVisibleItems == limit {
        return
      }
    }
  }

  private func appendUnpinnedItemsUntilLimit(_ limit: Int) {
    var limit = limit
    for indexedItem in indexedItems.filter({ $0.item.pin == nil }) {
      let menuItems = indexedItem.menuItems.filter({ !historyMenuItems.contains($0) })
      if !menuItems.isEmpty, let lastItem = lastUnpinnedHistoryMenuItem {
        let index = index(of: lastItem) + 1 + previewMenuItemOffset
        safeInsertItem(indexedItem.previewMenuItem, at: index)
        menuItems.reversed().forEach { historyMenuItem in
          safeInsertItem(historyMenuItem, at: index)
          limit += 1
        }
      }

      if maxVisibleItems != 0 && maxVisibleItems == limit {
        return
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
      safeRemoveItem(indexedItem.previewMenuItem)
      indexedItem.menuItems.forEach(safeRemoveItem)

      if let removeIndex = indexedItems.firstIndex(of: indexedItem) {
        indexedItems.remove(at: removeIndex)
      }
    }
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

  private func offloadCurrentPreview() {
    previewThrottle.cancel()
    previewPopover?.close()
    previewPopover = nil
  }
}
// swiftlint:enable type_body_length
// swiftlint:enable file_length
