import AppKit.NSPasteboard
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

  private let source: Source

  init(source: Source, pageSize: Int = 100) {
    self.source = source
    self.pageSize = pageSize
  }

  /// Reset and load the window at the top of the list.
  @MainActor
  func load() throws {
    pages = []
    totalCount = try source.count()
    tallRowIndices = try source.tallRowIndices()
    try ensureRowsLoaded(0..<1)
  }

  /// Load the pages covering `rows` (plus one page of lookahead on each
  /// side), reusing already-loaded pages and dropping the rest.
  @MainActor
  func ensureRowsLoaded(_ rows: Range<Int>) throws {
    guard pageCount > 0 else {
      pages = []
      return
    }

    let target = pageRange(covering: rows)
    if pages.count == target.count && pages.first?.index == target.lowerBound {
      return
    }

    pages = try target.map { pageIndex in
      if let existing = pages.first(where: { $0.index == pageIndex }) {
        return existing
      }
      return Page(index: pageIndex, items: try source.fetch(offset: pageIndex * pageSize, limit: pageSize))
    }
  }

  /// Recount and refetch the current window after the source was mutated
  /// (item added, removed, pinned, or history cleared). Contents may have
  /// shifted arbitrarily, so previously fetched pages are not reused.
  @MainActor
  func refresh() throws {
    totalCount = try source.count()
    tallRowIndices = try source.tallRowIndices()

    guard pageCount > 0 else {
      pages = []
      return
    }

    let first = min(pages.first?.index ?? 0, pageCount - 1)
    let last = min(max(pages.last?.index ?? 0, first), pageCount - 1)
    pages = try (first...last).map { pageIndex in
      Page(index: pageIndex, items: try source.fetch(offset: pageIndex * pageSize, limit: pageSize))
    }
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
final class HistoryPaginationSource: PaginatedItemSource {
  private static var imageContentTypes: [String] {
    [
      NSPasteboard.PasteboardType.tiff.rawValue,
      NSPasteboard.PasteboardType.png.rawValue,
      NSPasteboard.PasteboardType.jpeg.rawValue,
      NSPasteboard.PasteboardType.heic.rawValue
    ]
  }

  /// Decorators are reused across fetches so that SwiftUI identity and the
  /// current selection survive window shifts and refreshes. Values are weak:
  /// once a page is dropped and nothing else references its decorators, the
  /// entries die with them.
  private struct WeakDecorator {
    weak var value: HistoryItemDecorator?
  }
  private var decorators: [PersistentIdentifier: WeakDecorator] = [:]

  @MainActor
  func count() throws -> Int {
    decorators = decorators.filter { $0.value.value != nil }
    return try Storage.shared.context.fetchCount(
      FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.pin == nil })
    )
  }

  @MainActor
  func fetch(offset: Int, limit: Int) throws -> [HistoryItemDecorator] {
    var descriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil },
      sortBy: [Self.sortDescriptor()]
    )
    descriptor.fetchLimit = limit
    descriptor.fetchOffset = offset

    return try Storage.shared.context.fetch(descriptor).map(decorator(for:))
  }

  /// Indices (in the paged ordering) of unpinned items that contain an
  /// image. Presence is determined from content types alone so no image
  /// data is loaded or decoded.
  @MainActor
  func tallRowIndices() throws -> [Int] {
    let types = Self.imageContentTypes
    let contentDescriptor = FetchDescriptor<HistoryItemContent>(
      predicate: #Predicate { types.contains($0.type) }
    )
    let imageItemIDs = Set(
      try Storage.shared.context.fetch(contentDescriptor).compactMap { $0.item?.persistentModelID }
    )
    guard !imageItemIDs.isEmpty else { return [] }

    let itemDescriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil },
      sortBy: [Self.sortDescriptor()]
    )
    return try Storage.shared.context.fetch(itemDescriptor)
      .enumerated()
      .filter { imageItemIDs.contains($0.element.persistentModelID) }
      .map(\.offset)
  }

  private func decorator(for item: HistoryItem) -> HistoryItemDecorator {
    let id = item.persistentModelID
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
