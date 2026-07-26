import Foundation

/// A page of history items that can be shared between caches.
/// Implements Sequence for lazy iteration without creating intermediate arrays.
class Page: Sequence, ExpressibleByArrayLiteral {
  var items: [HistoryItemDecorator]
  var isValid: Bool = true

  init(_ items: [HistoryItemDecorator] = []) {
    self.items = items
  }

  required convenience init(arrayLiteral elements: HistoryItemDecorator...) {
    self.init(elements)
  }

  var count: Int { items.count }
  var isEmpty: Bool { items.isEmpty }

  func makeIterator() -> IndexingIterator<[HistoryItemDecorator]> {
    items.makeIterator()
  }

  func invalidate() {
    isValid = false
  }
}

/// A sequence that lazily concatenates multiple pages without creating intermediate arrays.
struct PageSequence: Sequence {
  let pages: [Page]

  init(_ pages: [Page]) {
    self.pages = pages
  }

  init(_ pages: Page...) {
    self.pages = pages
  }

  func makeIterator() -> Iterator {
    Iterator(pages: pages)
  }

  struct Iterator: IteratorProtocol {
    let pages: [Page]
    var pageIndex = 0
    var itemIndex = 0

    mutating func next() -> HistoryItemDecorator? {
      while pageIndex < pages.count {
        let page = pages[pageIndex]
        if itemIndex < page.items.count {
          let item = page.items[itemIndex]
          itemIndex += 1
          return item
        }
        pageIndex += 1
        itemIndex = 0
      }
      return nil
    }
  }

  /// Materialize the sequence into an array.
  /// Use this only when an array is actually needed.
  func toArray() -> [HistoryItemDecorator] {
    Array(self)
  }

  var count: Int {
    pages.reduce(0) { $0 + $1.count }
  }
}
