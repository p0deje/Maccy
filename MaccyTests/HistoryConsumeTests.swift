import Defaults
import SwiftData
import XCTest
@testable import Maccy

/// Tests for `History.consume(_:)`, the main-thread observer that applies the
/// `StoreEvent`s emitted by the off-main clipboard ingest actor.
///
/// Under the test plan's `enable-testing` launch argument `Storage.shared` is an
/// in-memory SwiftData store, so a save on the main context is immediately
/// observable. These tests simulate the actor's already-committed result by
/// mutating the main context directly (the actor commits on a background context
/// whose saves merge into the main context via SwiftData's shared-store
/// propagation — SwiftData has no `automaticallyMergesChangesFromParent`, so a
/// committed save becomes visible to a subsequent main-context fetch).
///
/// We assert the outcomes `consume` must produce: the right item count,
/// decorator reuse by identity (so decoded images survive), and the merged
/// `numberOfCopies`.
@MainActor
final class HistoryConsumeTests: XCTestCase {
  private let stringType = NSPasteboard.PasteboardType.string.rawValue

  private var history = History.shared
  private var savedSize = 200
  private var savedSortBy = Defaults[.sortBy]

  override func setUp() async throws {
    try await super.setUp()
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

  override func tearDown() async throws {
    Defaults[.size] = savedSize
    Defaults[.sortBy] = savedSortBy
    try await super.tearDown()
  }

  // MARK: - .added

  /// Consuming an `.added` event populates `all`/`items` from the merged main context.
  func testConsumeAddedPopulatesAllFromMergedMainContext() {
    let item = insertItem(text: "hello")
    try? Storage.shared.context.save()

    history.consume(.added(snapshot(of: item)))

    XCTAssertEqual(history.all.count, 1)
    XCTAssertEqual(history.items.count, 1)
    XCTAssertEqual(history.all.first?.title, "hello")
  }

  /// A second `.added` consume reuses the existing decorator (by identity) and adds the new one.
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

  /// When not searching, an `.added` consume selects the newest item.
  func testConsumeAddedSelectsNewestItemWhenNotSearching() {
    let firstItem = insertItem(text: "first")
    try? Storage.shared.context.save()
    history.consume(.added(snapshot(of: firstItem)))

    guard let firstDecorator = history.all.first else {
      return XCTFail("Expected one decorator after first consume")
    }
    AppState.shared.navigator.select(item: firstDecorator)

    let secondItem = insertItem(text: "second")
    try? Storage.shared.context.save()
    history.consume(.added(snapshot(of: secondItem)))

    XCTAssertEqual(AppState.shared.navigator.selection.first?.title, "second")
  }

  // MARK: - .merged

  /// Consuming a `.merged` event replaces the prior decorator with the merged item.
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

  // MARK: - Incremental insert

  /// Incremental consume must produce the same order as a fresh full sort of the
  /// store — the binary-insertion ordering invariant.
  func testConsumeIncrementalOrderMatchesFullSort() {
    let timestamps: [TimeInterval] = [100, 300, 200, 500, 400]
    var items: [HistoryItem] = []
    for (index, timestamp) in timestamps.enumerated() {
      let item = insertItem(text: "item\(index)")
      item.firstCopiedAt = Date(timeIntervalSince1970: timestamp)
      items.append(item)
    }
    try? Storage.shared.context.save()

    // Consume in the given (out-of-sort) order.
    for item in items {
      history.consume(.added(snapshot(of: item)))
    }

    let sorter = Sorter()
    let fullSortTitles = sorter
      .sort((try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())) ?? [])
      .map(\.title)
    XCTAssertEqual(history.all.map(\.title), fullSortTitles)
  }

  /// A consume must drop decorators whose backing model is gone from the store
  /// (the ingestor trims oldest-unpinned every copy at steady state — by
  /// `lastCopiedAt`, not the UI sort, so `all` can't trim itself).
  func testConsumeRemovesDecoratorWhenStoreItemDeleted() {
    let itemA = insertItem(text: "a")
    let itemB = insertItem(text: "b")
    try? Storage.shared.context.save()
    history.consume(.added(snapshot(of: itemA)))
    history.consume(.added(snapshot(of: itemB)))
    XCTAssertEqual(history.all.count, 2)

    // Delete A from the store (as the ingestor's trim would), add C, consume —
    // the sync on C's consume must drop A's decorator.
    Storage.shared.context.delete(itemA)
    let itemC = insertItem(text: "c")
    try? Storage.shared.context.save()
    history.consume(.added(snapshot(of: itemC)))

    let titles = Set(history.all.map(\.title))
    XCTAssertFalse(titles.contains("a"), "store-deleted item must be removed from all")
    XCTAssertEqual(history.all.count, 2, "A dropped, C added → still 2")
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
