import AppKit

struct Selection<Item: Equatable> {
  var items: [Item]

  init(items: [Item] = []) {
    self.items = items
  }

  var isEmpty: Bool {
    return items.isEmpty
  }

  var count: Int {
    return items.count
  }

  var first: Item? {
    return items.first
  }

  func first(where condition: (Item) -> Bool) -> Item? {
    return items.first(where: condition)
  }

  func forEach(_ body: (Int, Item) throws -> Void) rethrows {
    try items.enumerated().forEach(body)
  }

  mutating func remove(_ item: Item) {
    items.removeAll { $0 == item }
  }

  mutating func add(_ item: Item) {
    items.append(item)
  }
}
