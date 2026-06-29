import XCTest
@testable import Maccy

/// Verifies that `History` surfaces persistence errors via `lastPersistError` instead of crashing, and leaves its in-memory state untouched on failure.
@MainActor
class IngestErrorPropagationTests: XCTestCase {
  /// A failed insert records the error and leaves both `all` and `items` empty.
  func testAddSurfacesInsertErrorAndDoesNotMutateMemory() {
    let persistence = FailingHistoryPersistence()
    persistence.insertError = TestPersistenceError.expected
    let history = History(
      persistence: persistence,
      shouldInsertItemsInAdd: true,
      logsPersistenceErrors: false
    )

    _ = history.add(HistoryItem())

    XCTAssertTrue(history.all.isEmpty)
    XCTAssertTrue(history.items.isEmpty)
    XCTAssertNotNil(history.lastPersistError)
  }

  /// A failed `clear()` records the error and preserves the existing in-memory items.
  func testClearSurfacesDeleteErrorAndKeepsMemoryState() {
    let persistence = FailingHistoryPersistence()
    persistence.deleteUnpinnedError = TestPersistenceError.expected
    let history = History(persistence: persistence, logsPersistenceErrors: false)
    let item = HistoryItemDecorator(HistoryItem())
    history.all = [item]
    history.items = [item]

    history.clear()

    XCTAssertEqual(history.all, [item])
    XCTAssertEqual(history.items, [item])
    XCTAssertNotNil(history.lastPersistError)
  }
}

/// Stand-in error type used to inject deterministic failures into the fake persistence.
private enum TestPersistenceError: Error {
  case expected
}

/// A `HistoryPersistence` double whose `insert` and `deleteUnpinned` throw when their injected errors are set; all other operations succeed as no-ops returning empty.
@MainActor
private final class FailingHistoryPersistence: HistoryPersistence {
  var insertError: Error?
  var deleteUnpinnedError: Error?

  func insert(_ item: HistoryItem) throws {
    if let insertError {
      throw insertError
    }
  }

  func delete(_ item: HistoryItem) throws {}

  func deleteUnpinned() throws {
    if let deleteUnpinnedError {
      throw deleteUnpinnedError
    }
  }

  func deleteAll() throws {}

  func save() throws {}

  func fetchAll() throws -> [HistoryItem] {
    []
  }

  func countHistoryItems() throws -> Int {
    0
  }

  func countHistoryItemContents() throws -> Int {
    0
  }
}
