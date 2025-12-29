import Defaults
import Foundation
import Observation
import SwiftData

/// Manages pagination for unlimited history with a sliding window approach.
/// Maintains three active pages (previous, current, next) plus cached first/last pages
/// for efficient CMD+UP/DOWN navigation.
@Observable
class PaginationManager {
  // MARK: - Configuration

  let pageSize = 100

  // MARK: - Page Storage

  /// The previous page of items (for scrolling up)
  private(set) var previousPage: Page = Page()

  /// The current visible page of items
  private(set) var currentPage: Page = Page()

  /// The next page of items (for scrolling down)
  private(set) var nextPage: Page = Page()

  /// Cached first page for CMD+UP instant navigation.
  /// When on page 0, this shares the same Page instance as currentPage.
  private(set) var firstPageCache: Page = Page()

  /// Cached last page for CMD+DOWN instant navigation
  private(set) var lastPageCache: Page = Page()

  // MARK: - State Tracking

  /// Current page index (0-based)
  private(set) var currentPageIndex: Int = 0

  /// The starting index of the current window in the total item list
  var windowStartIndex: Int {
    // previousPage starts at (currentPageIndex - 1) * pageSize
    // but if currentPageIndex is 0, there's no previous page
    if currentPageIndex == 0 {
      return 0
    }
    return (currentPageIndex - 1) * pageSize
  }

  /// The ending index of the current window in the total item list
  var windowEndIndex: Int {
    windowStartIndex + allLoadedItems.count
  }

  /// Total number of items in storage
  private(set) var totalCount: Int = 0

  /// Whether we are currently loading more items
  private(set) var isLoading: Bool = false

  /// Computed total page count
  var totalPageCount: Int {
    guard totalCount > 0 else { return 0 }
    return (totalCount + pageSize - 1) / pageSize
  }

  /// Whether there are more items to load after current window
  var hasMoreItemsAfter: Bool {
    let windowEnd = (currentPageIndex + 2) * pageSize
    return windowEnd < totalCount
  }

  /// Whether there are more items to load before current window
  var hasMoreItemsBefore: Bool {
    currentPageIndex > 0
  }

  /// All currently loaded items in order (previous + current + next).
  /// Uses PageSequence for lazy iteration, materialized to array for compatibility.
  var allLoadedItems: [HistoryItemDecorator] {
    PageSequence(previousPage, currentPage, nextPage).toArray()
  }

  /// Lazy sequence of all loaded items without materializing to array.
  var allLoadedItemsSequence: PageSequence {
    PageSequence(previousPage, currentPage, nextPage)
  }

  // MARK: - Dependencies

  private let sorter: Sorter

  // MARK: - Initialization

  init(sorter: Sorter = Sorter()) {
    self.sorter = sorter
  }

  // MARK: - Public API

  /// Initial load of the first pages
  @MainActor
  func load() async throws {
    isLoading = true
    defer { isLoading = false }

    // Reset state
    currentPageIndex = 0
    previousPage = Page()
    currentPage = Page()
    nextPage = Page()

    // Get total count
    let countDescriptor = FetchDescriptor<HistoryItem>()
    totalCount = (try? Storage.shared.context.fetchCount(countDescriptor)) ?? 0

    guard totalCount > 0 else { return }

    // Load first page as current
    currentPage = Page(try await fetchPage(at: 0))

    // First page cache shares the same instance as current page when on page 0
    firstPageCache = currentPage

    // Load next page if available
    if totalPageCount > 1 {
      nextPage = Page(try await fetchPage(at: 1))
    }

    // Cache last page if different from current window
    if totalPageCount > 2 {
      lastPageCache = Page(try await fetchPage(at: totalPageCount - 1))
    } else if totalPageCount == 2 {
      lastPageCache = nextPage
    } else {
      lastPageCache = firstPageCache
    }
  }

  /// Called when user scrolls to end of current page (down)
  @MainActor
  func loadNextWindow() async throws {
    guard !isLoading, hasMoreItemsAfter else { return }

    isLoading = true
    defer { isLoading = false }

    // Shift window forward
    previousPage = currentPage
    currentPage = nextPage
    currentPageIndex += 1

    // Fetch new next page
    let nextPageIndex = currentPageIndex + 1
    if nextPageIndex < totalPageCount {
      nextPage = Page(try await fetchPage(at: nextPageIndex))
    } else {
      nextPage = Page()
    }
  }

  /// Called when user scrolls to beginning of current page (up)
  @MainActor
  func loadPreviousWindow() async throws {
    guard !isLoading, hasMoreItemsBefore else { return }

    isLoading = true
    defer { isLoading = false }

    // Shift window backward
    nextPage = currentPage
    currentPage = previousPage
    currentPageIndex -= 1

    // Fetch new previous page
    let prevPageIndex = currentPageIndex - 1
    if prevPageIndex >= 0 {
      previousPage = Page(try await fetchPage(at: prevPageIndex))
    } else {
      previousPage = Page()
    }
  }

  /// Jump to first page (CMD+UP navigation)
  @MainActor
  func jumpToFirst() async throws {
    guard currentPageIndex > 0 else { return }

    isLoading = true
    defer { isLoading = false }

    currentPageIndex = 0
    previousPage = Page()

    // Use cached first page if valid, otherwise refetch
    if firstPageCache.isValid && !firstPageCache.isEmpty {
      currentPage = firstPageCache
    } else {
      currentPage = Page(try await fetchPage(at: 0))
      firstPageCache = currentPage
    }

    nextPage = totalPageCount > 1 ? Page(try await fetchPage(at: 1)) : Page()
  }

  /// Jump to last page (CMD+DOWN navigation)
  @MainActor
  func jumpToLast() async throws {
    let lastPageIndex = max(0, totalPageCount - 1)
    guard currentPageIndex < lastPageIndex else { return }

    isLoading = true
    defer { isLoading = false }

    currentPageIndex = lastPageIndex

    // Use cached last page if valid, otherwise refetch
    if lastPageCache.isValid && !lastPageCache.isEmpty {
      currentPage = lastPageCache
    } else {
      currentPage = Page(try await fetchPage(at: lastPageIndex))
      lastPageCache = currentPage
    }

    nextPage = Page()
    previousPage = lastPageIndex > 0 ? Page(try await fetchPage(at: lastPageIndex - 1)) : Page()
  }

  /// Handle new item being added to history.
  /// Invalidates caches and refetches the current window to ensure correct ordering.
  @MainActor
  func handleNewItem(_ decorator: HistoryItemDecorator) {
    totalCount += 1
    invalidateAndRefetch()
  }

  /// Handle item being removed from history.
  /// Invalidates caches and refetches the current window.
  @MainActor
  func handleItemRemoved(_ decorator: HistoryItemDecorator) {
    totalCount = max(0, totalCount - 1)
    invalidateAndRefetch()
  }

  /// Update total count (e.g., after clearing history)
  @MainActor
  func updateTotalCount(_ count: Int) {
    totalCount = count
    if count == 0 {
      previousPage = Page()
      currentPage = Page()
      nextPage = Page()
      firstPageCache = Page()
      lastPageCache = Page()
      currentPageIndex = 0
    }
  }

  /// Refresh first and last page caches
  @MainActor
  func refreshCaches() async throws {
    firstPageCache = Page(try await fetchPage(at: 0))
    if currentPageIndex == 0 {
      currentPage = firstPageCache
    }

    if totalPageCount > 1 {
      lastPageCache = Page(try await fetchPage(at: totalPageCount - 1))
    } else {
      lastPageCache = firstPageCache
    }
  }

  // MARK: - Private Helpers

  /// Invalidate all caches and refetch the current window.
  /// This ensures correct ordering regardless of sort mode.
  @MainActor
  private func invalidateAndRefetch() {
    // Invalidate caches
    firstPageCache.invalidate()
    lastPageCache.invalidate()

    // Refetch current window asynchronously
    Task { @MainActor in
      do {
        try await refetchCurrentWindow()
      } catch {
        // Log error but don't crash - the UI will show stale data
      }
    }
  }

  /// Refetch the current window (previous, current, next pages) from the database.
  @MainActor
  private func refetchCurrentWindow() async throws {
    isLoading = true
    defer { isLoading = false }

    // Adjust current page index if we're now beyond the valid range
    let maxPageIndex = max(0, totalPageCount - 1)
    if currentPageIndex > maxPageIndex {
      currentPageIndex = maxPageIndex
    }

    // Fetch current page
    currentPage = Page(try await fetchPage(at: currentPageIndex))

    // Update first page cache if on first page
    if currentPageIndex == 0 {
      firstPageCache = currentPage
    } else if !firstPageCache.isValid {
      firstPageCache = Page(try await fetchPage(at: 0))
    }

    // Fetch previous page
    if currentPageIndex > 0 {
      previousPage = Page(try await fetchPage(at: currentPageIndex - 1))
    } else {
      previousPage = Page()
    }

    // Fetch next page
    if currentPageIndex + 1 < totalPageCount {
      nextPage = Page(try await fetchPage(at: currentPageIndex + 1))
    } else {
      nextPage = Page()
    }

    // Update last page cache if needed
    if !lastPageCache.isValid && totalPageCount > 0 {
      let lastIndex = totalPageCount - 1
      if lastIndex == currentPageIndex {
        lastPageCache = currentPage
      } else if lastIndex == currentPageIndex + 1 {
        lastPageCache = nextPage
      } else {
        lastPageCache = Page(try await fetchPage(at: lastIndex))
      }
    }
  }

  @MainActor
  private func fetchPage(at pageIndex: Int) async throws -> [HistoryItemDecorator] {
    let offset = pageIndex * pageSize
    var descriptor = FetchDescriptor<HistoryItem>(
      sortBy: [sortDescriptorForCurrentMode()]
    )
    descriptor.fetchLimit = pageSize
    descriptor.fetchOffset = offset

    let results = try Storage.shared.context.fetch(descriptor)
    return sorter.sort(results).map { HistoryItemDecorator($0) }
  }

  /// Returns the correct SortDescriptor based on user's sort preference
  private func sortDescriptorForCurrentMode() -> SortDescriptor<HistoryItem> {
    switch Defaults[.sortBy] {
    case .lastCopiedAt:
      return SortDescriptor(\.lastCopiedAt, order: .reverse)
    case .firstCopiedAt:
      return SortDescriptor(\.firstCopiedAt, order: .reverse)
    case .numberOfCopies:
      return SortDescriptor(\.numberOfCopies, order: .reverse)
    }
  }
}
