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
  private var maxPageSize: Int { pageSize * 2 }  // 200
  private var minPageSize: Int { pageSize / 2 }  // 50

  // MARK: - Page Storage

  /// The previous page of items (for scrolling up)
  private(set) var previousPage: [HistoryItemDecorator] = []

  /// The current visible page of items
  private(set) var currentPage: [HistoryItemDecorator] = []

  /// The next page of items (for scrolling down)
  private(set) var nextPage: [HistoryItemDecorator] = []

  /// Cached first page for CMD+UP instant navigation
  private(set) var firstPageCache: [HistoryItemDecorator] = []

  /// Cached last page for CMD+DOWN instant navigation
  private(set) var lastPageCache: [HistoryItemDecorator] = []

  // MARK: - State Tracking

  /// Current page index (0-based)
  private(set) var currentPageIndex: Int = 0

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

  /// All currently loaded items in order (previous + current + next)
  var allLoadedItems: [HistoryItemDecorator] {
    previousPage + currentPage + nextPage
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
    previousPage = []
    currentPage = []
    nextPage = []

    // Get total count
    let countDescriptor = FetchDescriptor<HistoryItem>()
    totalCount = (try? Storage.shared.context.fetchCount(countDescriptor)) ?? 0

    guard totalCount > 0 else { return }

    // Load first page as current
    currentPage = try await fetchPage(at: 0)

    // Load next page if available
    if totalPageCount > 1 {
      nextPage = try await fetchPage(at: 1)
    }

    // Cache first page (same as current initially)
    firstPageCache = currentPage

    // Cache last page if different from current window
    if totalPageCount > 2 {
      lastPageCache = try await fetchPage(at: totalPageCount - 1)
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
      nextPage = try await fetchPage(at: nextPageIndex)
    } else {
      nextPage = []
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
      previousPage = try await fetchPage(at: prevPageIndex)
    } else {
      previousPage = []
    }
  }

  /// Jump to first page (CMD+UP navigation)
  @MainActor
  func jumpToFirst() async throws {
    guard currentPageIndex > 0 else { return }

    isLoading = true
    defer { isLoading = false }

    currentPageIndex = 0
    previousPage = []
    currentPage = firstPageCache.isEmpty ? try await fetchPage(at: 0) : firstPageCache
    nextPage = totalPageCount > 1 ? try await fetchPage(at: 1) : []
  }

  /// Jump to last page (CMD+DOWN navigation)
  @MainActor
  func jumpToLast() async throws {
    let lastPageIndex = max(0, totalPageCount - 1)
    guard currentPageIndex < lastPageIndex else { return }

    isLoading = true
    defer { isLoading = false }

    currentPageIndex = lastPageIndex
    currentPage = lastPageCache.isEmpty ? try await fetchPage(at: lastPageIndex) : lastPageCache
    nextPage = []
    previousPage = lastPageIndex > 0 ? try await fetchPage(at: lastPageIndex - 1) : []
  }

  /// Handle new item being added to history
  func handleNewItem(_ decorator: HistoryItemDecorator) {
    // Remove from all pages if duplicate exists
    previousPage.removeAll { $0.item == decorator.item }
    currentPage.removeAll { $0.item == decorator.item }
    nextPage.removeAll { $0.item == decorator.item }

    // Insert at beginning of first page cache
    firstPageCache.insert(decorator, at: 0)

    // If we're on the first page, also update currentPage
    if currentPageIndex == 0 {
      currentPage.insert(decorator, at: 0)
    }

    // Split first page if too large
    if firstPageCache.count >= maxPageSize {
      splitFirstPage()
    }

    // Increment total count
    totalCount += 1

    // Check if any page is too small and needs reload
    validatePageSizes()
  }

  /// Handle item being removed from history
  func handleItemRemoved(_ decorator: HistoryItemDecorator) {
    previousPage.removeAll { $0 == decorator }
    currentPage.removeAll { $0 == decorator }
    nextPage.removeAll { $0 == decorator }
    firstPageCache.removeAll { $0 == decorator }
    lastPageCache.removeAll { $0 == decorator }

    totalCount = max(0, totalCount - 1)

    validatePageSizes()
  }

  /// Update total count (e.g., after clearing history)
  func updateTotalCount(_ count: Int) {
    totalCount = count
  }

  /// Refresh first and last page caches
  @MainActor
  func refreshCaches() async throws {
    firstPageCache = try await fetchPage(at: 0)
    if totalPageCount > 1 {
      lastPageCache = try await fetchPage(at: totalPageCount - 1)
    } else {
      lastPageCache = firstPageCache
    }
  }

  // MARK: - Private Helpers

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

  /// Split first page when it grows too large
  private func splitFirstPage() {
    guard firstPageCache.count >= maxPageSize else { return }

    // Keep first pageSize items in firstPageCache
    let overflow = Array(firstPageCache.dropFirst(pageSize))
    firstPageCache = Array(firstPageCache.prefix(pageSize))

    // If on first page, sync currentPage
    if currentPageIndex == 0 {
      currentPage = firstPageCache
      // Prepend overflow to nextPage
      nextPage = overflow + nextPage
    }
  }

  /// Check if pages are too small and need reload
  private func validatePageSizes() {
    // If current page is too small and there are more pages, trigger reload
    if currentPage.count < minPageSize && totalCount > pageSize {
      Task {
        try? await consolidatePages()
      }
    }
  }

  /// Consolidate pages when they become too small
  @MainActor
  private func consolidatePages() async throws {
    isLoading = true
    defer { isLoading = false }

    // Reload current window
    currentPage = try await fetchPage(at: currentPageIndex)

    if hasMoreItemsAfter {
      nextPage = try await fetchPage(at: currentPageIndex + 1)
    } else {
      nextPage = []
    }

    if hasMoreItemsBefore {
      previousPage = try await fetchPage(at: currentPageIndex - 1)
    } else {
      previousPage = []
    }
  }
}
