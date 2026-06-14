import Defaults
import SwiftData
import XCTest
@testable import Maccy

// Tests for `History.consume(_:)`, the main-thread observer that applies the
// `StoreEvent`s emitted by `BackgroundClipboardIngestor` (BS-2.2b). Under the
// test plan's `enable-testing` launch argument `Storage.shared` is an in-memory
// SwiftData store, so a save on the main context is immediately observable.
// These tests simulate the actor's *already-committed* result by mutating the
// main context directly (the actor commits on a background context whose saves
// merge into the main context once BS-2.3's
// `automaticallyMergesChangesFromParent` fix lands).
//
// We assert the OUTCOMES `consume` must produce: the right item count, decorator
// reuse by identity (so decoded images survive), and the merged `numberOfCopies`.
@MainActor
final class HistoryConsumeTests: XCTestCase {
  private let stringType = NSPasteboard.PasteboardType.string.rawValue

  private var history = History.shared
  private var savedSize = 200
  private var savedSortBy = Defaults[.sortBy]

  override func setUp() {
    super.setUp()
    // `Storage.shared` is an in-memory singleton shared across every test in
    // this run, so clear it (and the History view-model) in setUp so each test
    // starts from a known-empty state. Mirrors the
    // BackgroundClipboardIngestorTests setUp.
    try? Storage.shared.context.delete(model: HistoryItem.self)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()
    history.clearAll()
    history.searchQuery = ""

    savedSize = Defaults[.size]
    savedSortBy = Defaults[.sortBy]
    // Make the size limit large enough that the trim path never fires here.
    Defaults[.size] = 200
    Defaults[.sortBy] = .firstCopiedAt
  }

  override func tearDown() {
    Defaults[.size] = savedSize
    Defaults[.sortBy] = savedSortBy
    super.tearDown()
  }

  // MARK: - .added

  func testConsumeAddedPopulatesAllFromMergedMainContext() {
    let item = insertItem(text: "hello")
    try? Storage.shared.context.save()

    history.consume(.added(snapshot(of: item)))

    XCTAssertEqual(history.all.count, 1)
    XCTAssertEqual(history.items.count, 1)
    XCTAssertEqual(history.all.first?.title, "hello")
  }

  func testConsumeAddedReusesExistingDecoratorAndAddsNewItem() {
    let firstItem = insertItem(text: "first")
    try? Storage.shared.context.save()
    history.consume(.added(snapshot(of: firstItem)))

    guard let reusedDecorator = history.all.first else {
      return XCTFail("Expected one decorator after first consume")
    }

    let secondItem = insertItem(text: "second")
    try? Storage.shared.context.save()
    history.consume(.added(snapshot(of: secondItem)))

    XCTAssertEqual(history.all.count, 2)
    // The pre-existing decorator must be REUSED by persistentModelID (so decoded
    // images survive), not replaced with a freshly-built twin. Identity check.
    XCTAssertTrue(
      history.all.contains(where: { $0 === reusedDecorator }),
      "consume must reuse the existing decorator, not rebuild a new one"
    )
  }

  // MARK: - .merged

  func testConsumeMergedReflectsReplacedItem() {
    let original = insertItem(text: "dup")
    original.numberOfCopies = 1
    try? Storage.shared.context.save()
    history.consume(.added(snapshot(of: original)))

    // Simulate the actor's merge: delete the old item, insert the merged
    // successor (same content, incremented numberOfCopies), commit on the
    // (now-merged) main context.
    Storage.shared.context.delete(original)
    let merged = insertItem(text: "dup")
    merged.numberOfCopies = 3
    try? Storage.shared.context.save()

    history.consume(.merged(snapshot(of: merged)))

    XCTAssertEqual(history.all.count, 1, "Merge must produce a single decorator, not two")
    XCTAssertEqual(history.all.first?.item.numberOfCopies, 3)
    XCTAssertEqual(history.all.first?.title, "dup")
  }

  // MARK: - Helpers

  /// Inserts a single-string-content `HistoryItem` into the shared main context
  /// (mirrors the `historyItem(_:)` helper in HistoryTests).
  private func insertItem(text: String) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: stringType,
        value: text.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.numberOfCopies = 1
    item.title = item.generateTitle()
    return item
  }
}
