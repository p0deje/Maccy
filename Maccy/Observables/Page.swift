import Foundation

/// A fetched page of items. `index` is the page's position in the source's
/// paged ordering, so the page covers rows
/// `index * pageSize ..< index * pageSize + items.count`.
struct Page<Item> {
  let index: Int
  var items: [Item]
}

/// An ordered collection that can be counted and fetched in pages.
///
/// `PaginationManager` and `VirtualizedList` only talk to this protocol, so
/// they can be exercised in tests with arbitrary item types and synthetic
/// sources (e.g. a large list of numbers served in small pages).
protocol PaginatedItemSource {
  associatedtype Item

  /// Total number of items in the source.
  @MainActor
  func count() throws -> Int

  /// Items in `offset ..< offset + limit`, in the source's ordering.
  /// May return fewer than `limit` items at the end of the collection.
  @MainActor
  func fetch(offset: Int, limit: Int) throws -> [Item]

  /// Sorted indices of items that render at the tall row height
  /// (image items in Maccy's case). Empty if all rows share one height.
  @MainActor
  func tallRowIndices() throws -> [Int]
}

extension PaginatedItemSource {
  @MainActor
  func tallRowIndices() throws -> [Int] { [] }
}
