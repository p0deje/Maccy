import XCTest
@testable import Maccy

@MainActor
class IngestErrorPropagationTests: XCTestCase {
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

private enum TestPersistenceError: Error {
  case expected
}

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
