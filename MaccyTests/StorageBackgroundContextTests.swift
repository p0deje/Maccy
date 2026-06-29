import SwiftData
import XCTest
@testable import Maccy

/// Tests for storage context creation and the visible-window fetch loader.
@MainActor
class StorageBackgroundContextTests: XCTestCase {
  /// A background context is distinct from the main context and carries no undo
  /// manager, so background writes cannot pollute the main actor's undo stack.
  func testNewBackgroundContextCreatesSeparateContextWithoutUndo() {
    let backgroundContext = Storage.shared.newBackgroundContext()

    XCTAssertTrue(backgroundContext !== Storage.shared.context)
    XCTAssertNil(backgroundContext.undoManager)
  }

  // MARK: - VisibleWindowLoader

  private static let textType = "public.utf8-plain-text"

  /// Returns the shared in-memory context (`enable-testing`), cleared of all
  /// `HistoryItem` rows, rather than spinning up a fresh `ModelContainer`.
  ///
  /// A fresh container intermittently trips a SwiftData fatal error —
  /// "PersistentIdentifier remapped to a temporary identifier during save …
  /// fatal logic error in DefaultStore" — on `HistoryItemContent` relationships.
  /// The shared context handles the same insert-then-read pattern correctly and
  /// is what the rest of the suite uses, so each test clears it for isolation.
  private func makeContext() throws -> ModelContext {
    let context = Storage.shared.context
    for item in try context.fetch(FetchDescriptor<HistoryItem>()) {
      context.delete(item)
    }
    try context.save()
    return context
  }

  /// Inserts a single text-content `HistoryItem` with the given timing and copy
  /// count into `context`.
  @discardableResult
  private func insert(
    _ context: ModelContext,
    suffix: Int,
    lastCopiedAt: Date,
    numberOfCopies: Int = 1,
    firstCopiedAt: Date? = nil
  ) throws -> HistoryItem {
    let item = HistoryBuilder()
      .withContent(type: Self.textType, value: "item-\(suffix)".data(using: .utf8))
      .withNumberOfCopies(numberOfCopies)
      .build()
    item.firstCopiedAt = firstCopiedAt ?? lastCopiedAt
    item.lastCopiedAt = lastCopiedAt
    context.insert(item)
    return item
  }

  /// An empty store yields empty visible and tail windows.
  func testVisibleWindowEmptyStoreReturnsEmpty() throws {
    let context = try makeContext()
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .lastCopiedAt, fetchLimit: 10, visibleHint: 5
    )
    XCTAssertTrue(result.visible.isEmpty)
    XCTAssertTrue(result.tail.isEmpty)
  }

  /// The fetch splits the result into a visible window and tail by `visibleHint`.
  func testVisibleWindowSplitsByVisibleHint() throws {
    let context = try makeContext()
    for index in 0..<5 {
      try insert(context, suffix: index, lastCopiedAt: Date(timeIntervalSince1970: Double(1000 + index)))
    }
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .lastCopiedAt, fetchLimit: 5, visibleHint: 2
    )
    XCTAssertEqual(result.visible.count, 2)
    XCTAssertEqual(result.tail.count, 3)
  }

  /// Within the visible window items are newest-first by last-copied time, and
  /// every visible item is at least as recent as the oldest tail item.
  func testVisibleWindowOrdersLastCopiedAtDescendingAndVisiblePrecedesTail() throws {
    let context = try makeContext()
    for index in 0..<4 {
      try insert(context, suffix: index, lastCopiedAt: Date(timeIntervalSince1970: Double(1000 + index)))
    }
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .lastCopiedAt, fetchLimit: 4, visibleHint: 2
    )
    XCTAssertEqual(result.visible.count, 2)
    XCTAssertEqual(result.tail.count, 2)
    // newest first within the visible window
    XCTAssertEqual(result.visible.map(\.lastCopiedAt), result.visible.map(\.lastCopiedAt).sorted(by: >))
    // the visible window holds the newest items, the tail the older ones
    XCTAssertGreaterThanOrEqual(result.visible.first!.lastCopiedAt, result.tail.first!.lastCopiedAt)
  }

  /// The total number of fetched items respects `fetchLimit`.
  func testVisibleWindowRespectsFetchLimit() throws {
    let context = try makeContext()
    for index in 0..<10 {
      try insert(context, suffix: index, lastCopiedAt: Date(timeIntervalSince1970: Double(1000 + index)))
    }
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .lastCopiedAt, fetchLimit: 4, visibleHint: 2
    )
    XCTAssertEqual(result.visible.count + result.tail.count, 4)
    XCTAssertEqual(result.visible.count, 2)
    XCTAssertEqual(result.tail.count, 2)
  }

  /// A `visibleHint` larger than the item count places everything in the
  /// visible window and leaves the tail empty.
  func testVisibleWindowHintExceedingCountPutsAllInVisible() throws {
    let context = try makeContext()
    for index in 0..<3 {
      try insert(context, suffix: index, lastCopiedAt: Date(timeIntervalSince1970: Double(1000 + index)))
    }
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .lastCopiedAt, fetchLimit: 3, visibleHint: 99
    )
    XCTAssertEqual(result.visible.count, 3)
    XCTAssertTrue(result.tail.isEmpty)
  }

  /// Sorting by copy count orders the visible window most-copied first.
  func testVisibleWindowOrdersByNumberOfCopiesDescending() throws {
    let context = try makeContext()
    // identical lastCopiedAt isolates the numberOfCopies sort key
    let sameTimestamp = Date(timeIntervalSince1970: 1000)
    try insert(context, suffix: 1, lastCopiedAt: sameTimestamp, numberOfCopies: 1)
    try insert(context, suffix: 2, lastCopiedAt: sameTimestamp, numberOfCopies: 5)
    try insert(context, suffix: 3, lastCopiedAt: sameTimestamp, numberOfCopies: 3)
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .numberOfCopies, fetchLimit: 3, visibleHint: 3
    )
    XCTAssertEqual(result.visible.map(\.numberOfCopies), [5, 3, 1])
  }

  /// Sorting by first-copied time orders the visible window most-recent first.
  func testVisibleWindowOrdersByFirstCopiedAtDescending() throws {
    let context = try makeContext()
    // identical lastCopiedAt, distinct firstCopiedAt isolates the sort key
    let last = Date(timeIntervalSince1970: 2000)
    try insert(context, suffix: 1, lastCopiedAt: last, firstCopiedAt: Date(timeIntervalSince1970: 5000))
    try insert(context, suffix: 2, lastCopiedAt: last, firstCopiedAt: Date(timeIntervalSince1970: 1000))
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .firstCopiedAt, fetchLimit: 2, visibleHint: 2
    )
    XCTAssertEqual(
      result.visible.map(\.firstCopiedAt),
      [Date(timeIntervalSince1970: 5000), Date(timeIntervalSince1970: 1000)]
    )
  }
}
