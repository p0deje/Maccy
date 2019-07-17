import AppKit

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
class Menu: NSMenu, NSMenuDelegate {
  public let maxHotKey = 9

  required init(coder decoder: NSCoder) {
    super.init(coder: decoder)
  }

  override init(title: String) {
    super.init(title: title)
    self.delegate = self
  }

  func menuWillOpen(_ menu: NSMenu) {
    highlight(highlightableItems(items).first)
  }

  func addSearchItem() {
    let headerItemView = FilterMenuItemView(frame: NSRect(x: 0, y: 0, width: 20, height: 29))
    headerItemView.title = title

    let headerItem = NSMenuItem()
    headerItem.title = title
    headerItem.view = headerItemView
    headerItem.isEnabled = false

    addItem(headerItem)
  }

  func updateFilter(filter: String) {
    var index = 0
    for item in items[1...(items.count - 1)] {
      let itemMatchesFilter = validateItemWithFilter(item, filter)

      if itemMatchesFilter {
        item.isHidden = false
        highlight(item)
      } else {
        item.isHidden = true
      }

      if !isSystemItem(item: item) {
        if !item.isHidden && index < maxHotKey {
          index += 1
          item.keyEquivalent = String(index)
        } else {
          item.keyEquivalent = ""
        }
      }
    }
  }

  func select() {
    if let item = highlightedItem {
      performActionForItem(at: index(of: item))
      cancelTracking()
    }
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
    guard itemToHighlight != nil else {
      return
    }

    let highlightItemSelector = NSSelectorFromString("highlightItem:")
    perform(highlightItemSelector, with: itemToHighlight)
  }

  private func validateItemWithFilter(_ item: NSMenuItem, _ filter: String) -> Bool {
    if filter.isEmpty || item.isSeparatorItem || isSystemItem(item: item) {
      return true
    }

    if !item.isEnabled {
      return false
    }

    let range = item.title.range(
      of: filter,
      options: .caseInsensitive,
      range: nil,
      locale: nil
    )

    return (range != nil)
  }

  private func isSystemItem(item: NSMenuItem) -> Bool {
    let items = self.items.split(whereSeparator: { $0.isSeparatorItem })
    return items.count > 1 && items[1].contains(item)
  }
}
