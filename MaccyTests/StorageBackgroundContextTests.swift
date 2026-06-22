import SwiftData
import XCTest
@testable import Maccy

@MainActor
class StorageBackgroundContextTests: XCTestCase {
  func testNewBackgroundContextCreatesSeparateContextWithoutUndo() {
    let backgroundContext = Storage.shared.newBackgroundContext()

    XCTAssertTrue(backgroundContext !== Storage.shared.context)
    XCTAssertNil(backgroundContext.undoManager)
  }

  // MARK: - VisibleWindowLoader (BS-4.3)

  private static let textType = "public.utf8-plain-text"

  private func makeInMemoryContext() throws -> ModelContext {
    let container = try ModelContainer(
      for: HistoryItem.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return container.mainContext
  }

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

  func testVisibleWindowEmptyStoreReturnsEmpty() throws {
    let context = try makeInMemoryContext()
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .lastCopiedAt, fetchLimit: 10, visibleHint: 5
    )
    XCTAssertTrue(result.visible.isEmpty)
    XCTAssertTrue(result.tail.isEmpty)
  }

  func testVisibleWindowSplitsByVisibleHint() throws {
    let context = try makeInMemoryContext()
    for i in 0..<5 {
      try insert(context, suffix: i, lastCopiedAt: Date(timeIntervalSince1970: Double(1000 + i)))
    }
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .lastCopiedAt, fetchLimit: 5, visibleHint: 2
    )
    XCTAssertEqual(result.visible.count, 2)
    XCTAssertEqual(result.tail.count, 3)
  }

  func testVisibleWindowOrdersLastCopiedAtDescendingAndVisiblePrecedesTail() throws {
    let context = try makeInMemoryContext()
    for i in 0..<4 {
      try insert(context, suffix: i, lastCopiedAt: Date(timeIntervalSince1970: Double(1000 + i)))
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

  func testVisibleWindowRespectsFetchLimit() throws {
    let context = try makeInMemoryContext()
    for i in 0..<10 {
      try insert(context, suffix: i, lastCopiedAt: Date(timeIntervalSince1970: Double(1000 + i)))
    }
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .lastCopiedAt, fetchLimit: 4, visibleHint: 2
    )
    XCTAssertEqual(result.visible.count + result.tail.count, 4)
    XCTAssertEqual(result.visible.count, 2)
    XCTAssertEqual(result.tail.count, 2)
  }

  func testVisibleWindowHintExceedingCountPutsAllInVisible() throws {
    let context = try makeInMemoryContext()
    for i in 0..<3 {
      try insert(context, suffix: i, lastCopiedAt: Date(timeIntervalSince1970: Double(1000 + i)))
    }
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .lastCopiedAt, fetchLimit: 3, visibleHint: 99
    )
    XCTAssertEqual(result.visible.count, 3)
    XCTAssertTrue(result.tail.isEmpty)
  }

  func testVisibleWindowOrdersByNumberOfCopiesDescending() throws {
    let context = try makeInMemoryContext()
    // identical lastCopiedAt isolates the numberOfCopies sort key
    let ts = Date(timeIntervalSince1970: 1000)
    try insert(context, suffix: 1, lastCopiedAt: ts, numberOfCopies: 1)
    try insert(context, suffix: 2, lastCopiedAt: ts, numberOfCopies: 5)
    try insert(context, suffix: 3, lastCopiedAt: ts, numberOfCopies: 3)
    let result = try VisibleWindowLoader.fetchWindow(
      in: context, sortBy: .numberOfCopies, fetchLimit: 3, visibleHint: 3
    )
    XCTAssertEqual(result.visible.map(\.numberOfCopies), [5, 3, 1])
  }

  func testVisibleWindowOrdersByFirstCopiedAtDescending() throws {
    let context = try makeInMemoryContext()
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
