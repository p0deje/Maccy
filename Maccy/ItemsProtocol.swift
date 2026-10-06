protocol HasVisibility {
  var isVisible: Bool { get }
}

protocol ItemsContainer {
  associatedtype Item
  associatedtype Items: RandomAccessCollection where Items.Element == Item
  var containerVisible: Bool { get }
  var items: Items { get }
}

extension ItemsContainer {
    var containerVisible: Bool { true }
}

private extension ItemsContainer where Item: HasVisibility {}

extension ItemsContainer where Item: HasVisibility {

  var firstVisibleItem: Item? {
    guard containerVisible else { return nil }
    return self.items.first(where: \.isVisible)
  }
  func firstVisibleItem(where predicate: (Item) -> Bool) -> Item? {
    guard containerVisible else { return nil }
    return self.items.first { $0.isVisible && predicate($0) }
  }
  var lastVisibleItem: Item? {
    guard containerVisible else { return nil }
    return self.items.last(where: \.isVisible)
  }
  func lastVisibleItem(where predicate: (Item) -> Bool) -> Item? {
    guard containerVisible else { return nil }
    return self.items.last { $0.isVisible && predicate($0) }
  }
}

extension ItemsContainer where Item: HasVisibility, Item: Equatable {
  func visibleBetween(
    from fromItem: Item,
    to toItem: Item,
    inOrder: Bool = false
  ) -> [Item]? {
    guard containerVisible, fromItem.isVisible, toItem.isVisible else { return nil }
    guard let fromIndex = items.firstIndex(of: fromItem),
          let toIndex = items.firstIndex(of: toItem) else { return nil }

    let lowerBound = min(fromIndex, toIndex)
    let upperBound = max(fromIndex, toIndex)
    let range = items[lowerBound...upperBound].lazy.filter(\.isVisible)
    if !inOrder && fromIndex > toIndex {
      return Array(range.reversed())
    }
    return Array(range)
  }

  func nearestVisible(to item: Item, where predicate: (Item) -> Bool) -> Item? {
    guard containerVisible, item.isVisible else { return nil }
    return items.nearest(to: item) { $0.isVisible && predicate($0) }
  }

  func visibleItem(before: Item) -> Item? {
    return self.items.item(before: before, where: \.isVisible)
  }
  func visibleItem(after: Item) -> Item? {
    return self.items.item(after: after, where: \.isVisible)
  }
}
