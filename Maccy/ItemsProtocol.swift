/// A main-actor item that can be shown or hidden.
@MainActor
protocol HasVisibility {
  var isVisible: Bool { get }
}

/// A main-actor container of items that supports visibility-based navigation.
@MainActor protocol ItemsContainer {
  associatedtype Item
  var containerVisible: Bool { get }
  var items: [Item] { get set }
}

extension ItemsContainer {
    var containerVisible: Bool { true }
}

extension ItemsContainer where Item: HasVisibility {

  /// All currently visible items, or empty when the container is hidden.
  var visibleItems: [Item] {
    guard containerVisible else { return [] }
    return self.items.lazy.filter(\.isVisible)
  }

  /// The first visible item, or nil when the container is hidden.
  var firstVisibleItem: Item? {
    guard containerVisible else { return nil }
    return self.items.first(where: \.isVisible)
  }
  /// The first visible item matching `predicate`, or nil when hidden.
  func firstVisibleItem(where predicate: (Item) -> Bool) -> Item? {
    guard containerVisible else { return nil }
    return self.items.first { $0.isVisible && predicate($0) }
  }
  /// The last visible item, or nil when the container is hidden.
  var lastVisibleItem: Item? {
    guard containerVisible else { return nil }
    return self.items.last(where: \.isVisible)
  }
}

extension ItemsContainer where Item: HasVisibility, Item: Equatable {
  /// The visible item immediately before `item`, if any.
  func visibleItem(before: Item) -> Item? {
    return self.items.item(before: before, where: \.isVisible)
  }
  /// The visible item immediately after `item`, if any.
  func visibleItem(after: Item) -> Item? {
    return self.items.item(after: after, where: \.isVisible)
  }
}
