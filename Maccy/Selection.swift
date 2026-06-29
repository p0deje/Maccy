import AppKit

/// An ordered, deduplicated-by-identity selection of equatable items.
struct Selection<Item: Equatable> {
  /// The selected items in insertion order.
  var items: [Item]

  init(items: [Item] = []) {
    self.items = items
  }

  /// True when nothing is selected.
  var isEmpty: Bool {
    return items.isEmpty
  }

  /// Number of selected items.
  var count: Int {
    return items.count
  }

  /// The first selected item, if any.
  var first: Item? {
    return items.first
  }

  /// Calls `body` with each `(index, item)` pair.
  func forEach(_ body: (Int, Item) throws -> Void) rethrows {
    try items.enumerated().forEach(body)
  }

  /// Removes all occurrences equal to `item`.
  mutating func remove(_ item: Item) {
    items.removeAll { $0 == item }
  }

  /// Appends `item` to the selection.
  mutating func add(_ item: Item) {
    items.append(item)
  }
}
