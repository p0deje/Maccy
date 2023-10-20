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
    let popoverAnchor: NSMenuItem?

    init(value: String, item: HistoryItem?, menuItems: [HistoryMenuItem]) {
      self.value = value
      self.item = item
      self.menuItems = menuItems
      if #unavailable(macOS 14) {
        self.popoverAnchor = HistoryMenuItem.PreviewMenuItem()
      } else {
        self.popoverAnchor = HistoryMenuItem.PreviewMenuItem()
      }
    }
  }

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

  private static let subsequentPreviewDelay = 0.2
  private var initialPreviewDelay: Double { Double(UserDefaults.standard.previewDelay) / 1000 }
  private lazy var previewThrottle = Throttler(minimumDelay: initialPreviewDelay)
  private var previewPopover: NSPopover?

  private let historyMenuItemOffset = 1 // The first item is reserved for header.
  private let historyMenuItemsGroup = 3 // 1 main and 2 alternates
  private let previewMenuItemOffset = if #unavailable(macOS 14) { 1 } else { 0 }

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

  enum PopupLocation {
    case inMenuBar
    case atMouseCursor(location: CGPoint)
    case centeredInWindow(frame: CGRect)
    case centeredInScreen(frame: CGRect)
  }

  private var lastMenuLocation : PopupLocation?
  private var menuWindow: NSWindow? {
    NSApp.windows.first(where: { String(describing: type(of: $0)) == "NSPopupMenuWindow" })
  }

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

  func popUpMenu(at location: NSPoint, ofType locationType: PopupLocation) {
    prepareForPopup(location: locationType)
    super.popUp(positioning: nil, at: location, in: nil)
  }

  func prepareForPopup(location : PopupLocation) {
    lastMenuLocation = location
    updateUnpinnedItemsVisibility()
    setKeyEquivalents(historyMenuItems)
  }

  func menuWillOpen(_ menu: NSMenu) {
    isVisible = true
    previewThrottle.minimumDelay = initialPreviewDelay
    highlight(firstVisibleUnpinnedHistoryMenuItem ?? historyMenuItems.first)
  }

  internal func adjustMenuWindowPosition() {
    guard let location = lastMenuLocation else {
      return
    }
    switch location {
    case let .centeredInWindow(frame),
         let .centeredInScreen(frame):
      let centeredRect = NSRect.centered(ofSize: size, in: frame)
      menuWindow?.setFrameTopLeftPoint(NSPoint(x: centeredRect.minX, y: centeredRect.minY))
    default:
      break
    }
  }

  func menuDidClose(_ menu: NSMenu) {
    isVisible = false
    lastMenuLocation = nil
    offloadCurrentPreview()

    if let headerView = menuHeader() {
      DispatchQueue.main.async {
        headerView.setQuery("")
        headerView.queryField.refusesFirstResponder = true
      }
    }
  }

  private func menuHeader() -> MenuHeaderView? {
    return items.first?.view as? MenuHeaderView
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    offloadCurrentPreview()

    guard let item = item as? HistoryMenuItem else {
      return
    }

    previewThrottle.throttle { [self] in
      previewPopover = NSPopover()
      previewPopover?.animates = false
      previewPopover?.behavior = .semitransient
      previewPopover?.contentViewController = Preview(item: item.item)

      guard let previewWindow = menuWindow,
            let windowContentView = previewWindow.contentView,
            let boundsOfVisibleMenuItem = boundsOfMenuItem(item, windowContentView) else {
        return
      }

      previewThrottle.minimumDelay = Menu.subsequentPreviewDelay

      previewPopover?.show(
        relativeTo: boundsOfVisibleMenuItem,
        of: windowContentView,
        preferredEdge: .maxX
      )

      if let popoverWindow = previewPopover?.contentViewController?.view.window {
        if popoverWindow.frame.minX < previewWindow.frame.minX {
          popoverWindow.setFrameOrigin(
            NSPoint(x: popoverWindow.frame.minX - Menu.popoverGap, y: popoverWindow.frame.minY)
          )
        } else {
          popoverWindow.setFrameOrigin(
            NSPoint(x: popoverWindow.frame.minX + Menu.popoverGap, y: popoverWindow.frame.minY)
          )
        }
      }
    }
  }

  private func boundsOfMenuItem(_ item: NSMenuItem, _ windowContentView: NSView) -> NSRect? {
    let windowRectInScreenCoordinates = windowContentView.accessibilityFrame()
    let menuItemRectInScreenCoordinates = item.accessibilityFrame()
    return NSRect(
      origin: NSPoint(
        x: menuItemRectInScreenCoordinates.origin.x - windowRectInScreenCoordinates.origin.x,
        y: menuItemRectInScreenCoordinates.origin.y - windowRectInScreenCoordinates.origin.y),
      size: menuItemRectInScreenCoordinates.size
    )
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
        if #unavailable(macOS 14) {
          safeAddItem(indexedItem.popoverAnchor!)
        }
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
      if #unavailable(macOS 14) {
        self.safeInsertItem(indexedItem.popoverAnchor!, at: menuItemInsertionIndex)
      }

      for menuItem in menuItems.reversed() {
        self.safeInsertItem(menuItem, at: menuItemInsertionIndex)
      }

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
    if maxMenuItems > 0 && maxMenuItems < results.count {
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
        indexedItem.menuItems.forEach(safeRemoveItem)
      }
      if #unavailable(macOS 14) {
        self.safeRemoveItem(indexedItem.popoverAnchor)
      }
    }

    // Second, update order of items to match search results order.
    for result in results.reversed() {
      if #unavailable(macOS 14),
         let popoverAnchor = result.object.popoverAnchor {
        safeRemoveItem(popoverAnchor)
        safeInsertItem(popoverAnchor, at: historyMenuItemOffset)
      }
      for menuItem in result.object.menuItems.reversed() {
        safeRemoveItem(menuItem)
        menuItem.highlight(result.titleMatches)
        safeInsertItem(menuItem, at: historyMenuItemOffset)
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
        if #unavailable(macOS 14) {
          safeRemoveItem(indexedItem.popoverAnchor)
        }

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
      if #unavailable(macOS 14) {
        safeRemoveItem(historyItem.popoverAnchor)
      }
    } else {
      let pin = HistoryItem.randomAvailablePin
      for menuItem in historyItem.menuItems {
        menuItem.pin(pin)
        safeRemoveItem(menuItem)
      }
      if #unavailable(macOS 14) {
        safeRemoveItem(historyItem.popoverAnchor)
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
      if #unavailable(macOS 14) {
        safeInsertItem(historyItem.popoverAnchor!, at: menuItemIndex)
      }
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
      if #unavailable(macOS 14) {
        safeRemoveItem(indexedItem.popoverAnchor)
      }
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
        if #unavailable(macOS 14) {
          safeRemoveItem(indexedItem.popoverAnchor)
        }
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
        if #unavailable(macOS 14) {
          safeInsertItem(indexedItem.popoverAnchor!, at: index)
        }
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
      if #unavailable(macOS 14) {
        safeRemoveItem(indexedItem.popoverAnchor)
      }
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
