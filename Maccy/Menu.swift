import AppKit

// Custom menu supporting "search-as-you-type" based on https://github.com/mikekazakov/MGKMenuWithFilter.
class Menu: NSMenu {
  required init(coder decoder: NSCoder) {
    super.init(coder: decoder)
  }

  override init(title: String) {
    super.init(title: title)
  }

  func addSearchItem(){
    let headerItemView = FilterMenuItemView(frame: NSRect(x: 0, y: 0, width: 20, height: 21))
    headerItemView.title = title

    let headerItem = NSMenuItem()
    headerItem.title = title
    headerItem.view = headerItemView

    addItem(headerItem)
  }

  func updateFilter(filter: String) {
    var i = 0;
    for item in items[1...(items.count - 1)] {
      item.isHidden = !validateItemWithFilter(item, filter)
      if !item.isHidden {
        i = i + 1
        item.keyEquivalent = String(i)
      } else {
        item.keyEquivalent = ""
      }
    }

    if highlightedItem == nil || highlightedItem?.isHidden == true {
      var itemToHighlight: NSMenuItem?
      for item in items[1...(items.count - 1)] {
        if !item.isHidden && item.isEnabled {
          itemToHighlight = item
          break
        }
      }

      if itemToHighlight != nil {
        let highlightItemSelector = NSSelectorFromString("highlightItem:")
        perform(highlightItemSelector, with: itemToHighlight)
      }
    }
  }

  private func validateItemWithFilter(_ item: NSMenuItem, _ filter: String) -> Bool {
    if filter.isEmpty || item.isSeparatorItem{
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
}
