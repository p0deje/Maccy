protocol HasVisibility {
  var isVisible: Bool { get }
}

protocol ItemsContainer {
  associatedtype Item
  var containerVisible: Bool { get }
  var items: [Item] { get set }
}

extension ItemsContainer {
    var containerVisible: Bool { true }
}

private extension ItemsContainer where Item: HasVisibility {}

extension ItemsContainer where Item: HasVisibility {

  var visibleItems: [Item] {
    guard containerVisible else { return [] }
    return self.items.lazy.filter(\.isVisible)
  }

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
  func visibleItem(before: Item) -> Item? {
    return self.items.item(before: before, where: \.isVisible)
  }
  func visibleItem(after: Item) -> Item? {
    return self.items.item(after: after, where: \.isVisible)
  }
}
