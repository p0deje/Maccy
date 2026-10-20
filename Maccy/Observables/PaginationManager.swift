import Defaults
import Foundation
import Observation
import SwiftData

/// Keeps a sliding window of pages over a `PaginatedItemSource`.
///
/// The window is addressed by row index: the view derives the visible rows
/// from its scroll offset and calls `ensureRowsLoaded`, which fetches the
/// pages covering those rows plus one page of lookahead on each side and
/// drops every other page. Mapping the scroll position to page indices
/// directly (instead of reacting to sentinel views appearing) makes loading
/// reliable regardless of how fast the user scrolls.
@Observable
class PaginationManager<Source: PaginatedItemSource> {
  typealias Item = Source.Item

  let pageSize: Int

  /// Total number of items in the source.
  private(set) var totalCount: Int = 0

  /// Sorted indices of rows that render at the tall row height.
  private(set) var tallRowIndices: [Int] = []

  /// Contiguous run of loaded pages, ascending by page index.
  private(set) var pages: [Page<Item>] = []

  var pageCount: Int {
    guard totalCount > 0 else { return 0 }
    return (totalCount + pageSize - 1) / pageSize
  }

  /// Row index of the first loaded item.
  var windowStartIndex: Int {
    (pages.first?.index ?? 0) * pageSize
  }

  /// Rows currently backed by loaded items.
  var loadedRange: Range<Int> {
    let start = windowStartIndex
    return start ..< start + pages.reduce(0) { $0 + $1.items.count }
  }

  var loadedItems: [Item] {
    pages.flatMap(\.items)
  }

  let source: Source

  init(source: Source, pageSize: Int = 100) {
    self.source = source
    self.pageSize = pageSize
  }

  /// Reset and load the window at the top of the list.
  ///
  /// Like `refresh`, this either succeeds completely or leaves the manager
  /// unchanged: `totalCount` must never disagree with `pages`, because the
  /// view sizes the scrollable area from the count while rendering only
  /// loaded rows. A partial update would show a huge empty list.
  @MainActor
  func load() throws {
    let count = try source.count()
    let tallRows = try source.tallRowIndices()

    pages = []
    totalCount = count
    tallRowIndices = tallRows
    try ensureRowsLoaded(0..<1)
  }

  /// Load the pages covering `rows` (plus one page of lookahead on each
  /// side), reusing already-loaded pages and dropping the rest. If a fetch
  /// throws, the previous window stays in place; the next scroll retries.
  @MainActor
  func ensureRowsLoaded(_ rows: Range<Int>) throws {
    guard pageCount > 0 else {
      pages = []
      return
    }

    let target = pageRange(covering: rows)
    if pages.count == target.count && pages.first?.index == target.lowerBound && pages.allSatisfy(isReusable) {
      return
    }

    pages = try target.map { pageIndex in
      if let existing = pages.first(where: { $0.index == pageIndex }), isReusable(existing) {
        return existing
      }
      return Page(index: pageIndex, items: try source.fetch(offset: pageIndex * pageSize, limit: pageSize))
    }
  }

  /// Recount and refetch the current window after the source was mutated
  /// (item added, removed, pinned, or history cleared). Contents may have
  /// shifted arbitrarily, so previously fetched pages are not reused.
  /// Applies all state at once: if any fetch throws, nothing changes.
  @MainActor
  func refresh() throws {
    let count = try source.count()
    let tallRows = try source.tallRowIndices()
    let newPageCount = count > 0 ? (count + pageSize - 1) / pageSize : 0

    var newPages: [Page<Item>] = []
    if newPageCount > 0 {
      let first = min(pages.first?.index ?? 0, newPageCount - 1)
      let last = min(max(pages.last?.index ?? 0, first), newPageCount - 1)
      newPages = try (first...last).map { pageIndex in
        Page(index: pageIndex, items: try source.fetch(offset: pageIndex * pageSize, limit: pageSize))
      }
    }

    totalCount = count
    tallRowIndices = tallRows
    pages = newPages
  }

  /// A cached page can be reused only while its size is still plausible:
  /// full, or the (possibly short) last page. A short page that is no
  /// longer the last page was fetched when the store was smaller and would
  /// leave rows below it permanently empty.
  private func isReusable(_ page: Page<Item>) -> Bool {
    page.items.count == pageSize || page.index == pageCount - 1
  }

  private func pageRange(covering rows: Range<Int>) -> ClosedRange<Int> {
    let lastRow = min(totalCount - 1, max(rows.upperBound - 1, rows.lowerBound))
    let firstRow = min(max(0, rows.lowerBound), lastRow)
    let firstPage = max(0, firstRow / pageSize - 1)
    let lastPage = min(pageCount - 1, lastRow / pageSize + 1)
    return firstPage...max(firstPage, lastPage)
  }
}

/// Serves unpinned history items from SwiftData in the order defined by the
/// user's sort preference. Pinned items are excluded: they are always fully
/// loaded and rendered separately, so pages and row indices line up exactly
/// with the unpinned list on screen. Must be used from the main actor, where
/// `Storage.shared`'s main-context lives.
///
/// `count()` takes an ordered snapshot of the store (no contents are loaded),
/// and `fetch`/`tallRowIndices` slice that snapshot. Slicing in memory instead
/// of using `fetchOffset` matters: SwiftData has been observed to ignore
/// `fetchOffset` and return the first `fetchLimit` rows for every page, which
/// duplicated pages and broke the list.
///
/// The snapshot is kept until `invalidate()` is called. Frequent mutations
/// (an item is copied, deleted, pinned or unpinned) update it in place with
/// `insert` and `remove`, so they do not refetch the whole history.
final class HistoryPaginationSource: PaginatedItemSource {
  /// Decorators are reused across fetches so that SwiftUI identity and the
  /// current selection survive window shifts and refreshes. Values are weak:
  /// once a page is dropped and nothing else references its decorators, the
  /// entries die with them.
  private struct WeakDecorator {
    weak var value: HistoryItemDecorator?
  }
  private var decorators: [ObjectIdentifier: WeakDecorator] = [:]

  private struct Entry {
    let item: HistoryItem
    let isTall: Bool
  }

  /// Ordered snapshot of all unpinned items.
  private var entries: [Entry] = []
  private var needsSnapshot = true

  /// Drop the snapshot, so the next `count()` refetches it from storage.
  func invalidate() {
    needsSnapshot = true
  }

  @MainActor
  func count() throws -> Int {
    if needsSnapshot {
      try takeSnapshot()
    }
    return entries.count
  }

  @MainActor
  func fetch(offset: Int, limit: Int) throws -> [HistoryItemDecorator] {
    guard offset < entries.count else { return [] }

    return entries[offset ..< min(entries.count, offset + limit)].map { decorator(for: $0.item) }
  }

  /// Indices (in the paged ordering) of unpinned items that contain an image.
  @MainActor
  func tallRowIndices() throws -> [Int] {
    entries.indices.filter { entries[$0].isTall }
  }

  /// Insert a stored unpinned item at its sorted position. Later fetches
  /// return `decorator` for it.
  @MainActor
  func insert(_ decorator: HistoryItemDecorator) {
    let item = decorator.item
    decorators[ObjectIdentifier(item)] = WeakDecorator(value: decorator)
    guard !needsSnapshot, item.pin == nil else { return }

    remove(item)
    let index = insertionIndex(for: item, by: Defaults[.sortBy])
    entries.insert(Entry(item: item, isTall: Self.hasImage(item)), at: index)
  }

  /// Remove an item, for example after it was deleted or pinned.
  @MainActor
  func remove(_ item: HistoryItem) {
    guard !needsSnapshot else { return }

    entries.removeAll { $0.item === item }
  }

  /// Decorators for the unpinned items that pass `isIncluded`, in sort order.
  /// Stops after `limit` matches.
  @MainActor
  func items(
    where isIncluded: (HistoryItem) -> Bool,
    limit: Int = .max
  ) throws -> [HistoryItemDecorator] {
    _ = try count()

    var result: [HistoryItemDecorator] = []
    for entry in entries where isIncluded(entry.item) {
      result.append(decorator(for: entry.item))
      if result.count >= limit {
        break
      }
    }
    return result
  }

  /// The first unpinned item that passes `predicate`, in sort order.
  @MainActor
  func firstItem(where predicate: (HistoryItem) -> Bool) throws -> HistoryItem? {
    _ = try count()

    return entries.first { predicate($0.item) }?.item
  }

  @MainActor
  private func takeSnapshot() throws {
    decorators = decorators.filter { $0.value.value != nil }
    let items = try Storage.shared.context.fetch(
      FetchDescriptor<HistoryItem>(
        predicate: #Predicate { $0.pin == nil },
        sortBy: [Self.sortDescriptor()]
      )
    )
    let imageItemIDs = try Self.imageItemIDs()
    entries = items.map { Entry(item: $0, isTall: imageItemIDs.contains($0.persistentModelID)) }
    needsSnapshot = false
  }

  /// Identifiers of unpinned items that contain an image. The query only
  /// checks content types, so no content (image data) is loaded or decoded.
  @MainActor
  private static func imageItemIDs() throws -> Set<PersistentIdentifier> {
    let types = imageContentTypes
    return Set(
      try Storage.shared.context.fetchIdentifiers(
        FetchDescriptor<HistoryItem>(
          predicate: #Predicate { item in
            item.pin == nil && item.contents.contains { types.contains($0.type) }
          }
        )
      )
    )
  }

  private static var imageContentTypes: [String] {
    StorageType.images.types.map(\.rawValue)
  }

  @MainActor
  private static func hasImage(_ item: HistoryItem) -> Bool {
    let types = imageContentTypes
    return item.contents.contains { types.contains($0.type) }
  }

  /// Index of the first entry that does not sort before `item`, so a new item
  /// goes before existing items with the same sort key.
  @MainActor
  private func insertionIndex(for item: HistoryItem, by sortBy: Sorter.By) -> Int {
    var lower = 0
    var upper = entries.count
    while lower < upper {
      let mid = (lower + upper) / 2
      if Self.sortsBefore(entries[mid].item, item, by: sortBy) {
        lower = mid + 1
      } else {
        upper = mid
      }
    }
    return lower
  }

  @MainActor
  private static func sortsBefore(_ lhs: HistoryItem, _ rhs: HistoryItem, by sortBy: Sorter.By) -> Bool {
    switch sortBy {
    case .lastCopiedAt:
      lhs.lastCopiedAt > rhs.lastCopiedAt
    case .firstCopiedAt:
      lhs.firstCopiedAt > rhs.firstCopiedAt
    case .numberOfCopies:
      lhs.numberOfCopies > rhs.numberOfCopies
    }
  }

  private func decorator(for item: HistoryItem) -> HistoryItemDecorator {
    // A live decorator keeps its item alive, so the identifier stays unique.
    let id = ObjectIdentifier(item)
    if let existing = decorators[id]?.value {
      return existing
    }

    let decorator = HistoryItemDecorator(item)
    decorators[id] = WeakDecorator(value: decorator)
    return decorator
  }

  private static func sortDescriptor() -> SortDescriptor<HistoryItem> {
    switch Defaults[.sortBy] {
    case .lastCopiedAt:
      SortDescriptor(\.lastCopiedAt, order: .reverse)
    case .firstCopiedAt:
      SortDescriptor(\.firstCopiedAt, order: .reverse)
    case .numberOfCopies:
      SortDescriptor(\.numberOfCopies, order: .reverse)
    }
  }
}
