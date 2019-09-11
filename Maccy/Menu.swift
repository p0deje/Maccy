import AppKit

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
class Menu: NSMenu, NSMenuDelegate {
  public let maxHotKey = 9
  public var allItems: [NSMenuItem] = []
  public var history: History?

  private let menuWidth = 300
  private let search = Search()

  required init(coder decoder: NSCoder) {
    super.init(coder: decoder)
  }

  override init(title: String) {
    super.init(title: title)
    self.delegate = self
    self.minimumWidth = CGFloat(menuWidth)
  }

  func menuWillOpen(_ menu: NSMenu) {
    self.items = allItems
    setKeyEquivalents(items)
    highlight(highlightableItems(items).first)
  }

  override func addItem(_ newItem: NSMenuItem) {
    allItems.append(newItem)
    super.addItem(newItem)
  }

  override func removeItem(at index: Int) {
    allItems.remove(at: index)
    super.removeItem(at: index)
  }

  func addSearchItem() {
    let headerItemView = FilterMenuItemView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 29))
    headerItemView.title = title

    let headerItem = NSMenuItem()
    headerItem.title = title
    headerItem.view = headerItemView
    headerItem.isEnabled = false

    addItem(headerItem)
  }

  func updateFilter(filter: String) {
    let oldAllItems = allItems

    let searchItem = allItems.first
    let results = search.search(string: filter, within: searchableItems())
    let systemItems = allItems.filter({ isSystemItem(item: $0) })

    allItems.removeAll()
    items.removeAll()

    items = [searchItem!]
    items += results
    items += [NSMenuItem.separator()]
    items += systemItems

    allItems = oldAllItems

    setKeyEquivalents(items)
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

    if !isSystemItem(item: itemToRemove) {
      if let historyItemToRemove = itemToRemove as? HistoryMenuItem {
        if let fullTitle = historyItemToRemove.fullTitle {
          if let index = items.firstIndex(of: itemToRemove) {
            removeItem(at: index) // alternate
            removeItem(at: index - 1)
            history?.remove(fullTitle)
            setKeyEquivalents(items)
            highlight(items[index])
          }
        }
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
    if itemToHighlight != nil {
      perform(highlightItemSelector, with: itemToHighlight)
    }
  }

  private func setKeyEquivalents(_ items: [NSMenuItem]) {
    let mainItems = items.filter { !$0.isAlternate && !isSystemItem(item: $0) }
    let altItems = items.filter { $0.isAlternate }

    var index = 0
    for item in mainItems {
      if index <= maxHotKey {
        item.keyEquivalent = String(index)
        index += 1
      } else if !item.keyEquivalent.isEmpty {
        item.keyEquivalent = ""
      }
    }

    index = 1
    for item in altItems {
      if index <= maxHotKey {
        item.keyEquivalent = String(index)
        index += 1
      } else if !item.keyEquivalent.isEmpty {
        item.keyEquivalent = ""
      }
    }
  }

  private func searchableItems() -> [NSMenuItem] {
    return allItems.filter({ $0.isEnabled && !$0.isSeparatorItem && !isSystemItem(item: $0) })
  }

  private func isSystemItem(item: NSMenuItem) -> Bool {
    let items = allItems.split(whereSeparator: { $0.isSeparatorItem })
    return items.count > 1 && items[1].contains(item)
  }
}
