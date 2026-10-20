import AppKit
import Defaults
import Sauce
import SwiftData
import XCTest
@testable import Maccy

/// Exercises `History` in unlimited mode, where only a window of the
/// unpinned items is loaded and the rest stays in storage.
@MainActor
class UnlimitedHistoryTests: XCTestCase {
  let savedIgnoreEvents = Defaults[.ignoreEvents]
  let savedSearchMode = Defaults[.searchMode]
  let savedSortBy = Defaults[.sortBy]
  let savedUnlimited = Defaults[.isUnlimitedHistory]
  let history = History.shared

  // A valid 1x1 transparent PNG.
  static let pngData = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  )!

  override func setUp() async throws {
    try await super.setUp()
    // Clipboard polling started by other suites would insert captured items.
    Defaults[.ignoreEvents] = true
    Defaults[.searchMode] = .exact
    Defaults[.sortBy] = .lastCopiedAt
    Defaults[.isUnlimitedHistory] = true
    history.searchQuery = ""
    history.clearAll()
    try clearStore()
    try await history.load()
  }

  override func tearDown() async throws {
    history.searchQuery = ""
    history.clearAll()
    try clearStore()
    Defaults[.ignoreEvents] = savedIgnoreEvents
    Defaults[.searchMode] = savedSearchMode
    Defaults[.sortBy] = savedSortBy
    Defaults[.isUnlimitedHistory] = savedUnlimited
    try await super.tearDown()
  }

  func testLoadPagesUnpinnedItems() async throws {
    try await loadHistory(count: 250)
    storeItem(title: "pinned", ago: 30, pin: "a")
    try await history.load()

    XCTAssertEqual(history.unpinnedTotalCount, 250)
    XCTAssertEqual(history.totalCount, 251)
    XCTAssertEqual(history.unpinnedItems.count, 200)
    XCTAssertEqual(history.pinnedItems.map(\.title), ["pinned"])
  }

  func testAddingPutsNewItemFirst() async throws {
    try await loadHistory(count: 250)

    let added = history.add(newItem("new"))

    XCTAssertEqual(history.unpinnedTotalCount, 251)
    XCTAssertTrue(history.unpinnedItems.first === added)
    XCTAssertEqual(history.unpinnedItems[1].title, "item 0")
  }

  func testAddingDuplicateOfUnloadedItemMergesIt() async throws {
    try await loadHistory(count: 250)
    XCTAssertFalse(history.unpinnedItems.contains { $0.title == "item 240" })

    let merged = history.add(newItem("item 240"))

    XCTAssertEqual(history.unpinnedTotalCount, 250)
    XCTAssertTrue(history.unpinnedItems.first === merged)
    XCTAssertEqual(merged.item.numberOfCopies, 2)
    let stored = try Storage.shared.context.fetch(
      FetchDescriptor<HistoryItem>(predicate: #Predicate { $0.title == "item 240" })
    )
    XCTAssertEqual(stored.count, 1)
  }

  func testDeletingRemovesItemFromStore() async throws {
    try await loadHistory(count: 250)

    history.delete(history.unpinnedItems.first)

    XCTAssertEqual(history.unpinnedTotalCount, 249)
    XCTAssertEqual(history.unpinnedItems.first?.title, "item 1")
  }

  func testPinningMovesItemBetweenPinsAndPages() async throws {
    try await loadHistory(count: 250)
    let item = try XCTUnwrap(history.unpinnedItems.first)

    history.togglePin(item)
    XCTAssertTrue(item.isPinned)
    XCTAssertEqual(history.unpinnedTotalCount, 249)
    XCTAssertTrue(history.pinnedItems.contains(item))
    XCTAssertFalse(history.unpinnedItems.contains(item))

    history.togglePin(item)
    XCTAssertTrue(item.isUnpinned)
    XCTAssertEqual(history.unpinnedTotalCount, 250)
    XCTAssertTrue(history.unpinnedItems.first === item)
  }

  func testSearchCoversUnloadedItems() async throws {
    try await loadHistory(count: 250)

    try await search("item 245")

    XCTAssertEqual(history.unpinnedItems.map(\.title), ["item 245"])
  }

  func testSearchResultsAreLimited() async throws {
    try await loadHistory(count: 1_050)

    try await search("item")

    XCTAssertEqual(history.unpinnedItems.count, 1_000)
    XCTAssertEqual(history.unpinnedItems.first?.title, "item 0")
  }

  func testNumericShortcutsOnlyWhileWindowIsAtTop() async throws {
    try await loadHistory(count: 450)
    XCTAssertEqual(history.unpinnedItems.first?.shortcuts.first?.key, Key(character: "1", virtualKeyCode: nil))

    history.ensureLoaded(rows: 300..<310)
    XCTAssertEqual(history.loadedRange, 200..<450)
    XCTAssertTrue(history.unpinnedItems.allSatisfy { $0.shortcuts.isEmpty })

    history.ensureLoaded(rows: 0..<10)
    XCTAssertEqual(history.unpinnedItems.first?.shortcuts.first?.key, Key(character: "1", virtualKeyCode: nil))
  }

  func testImageRowsAreTall() async throws {
    for index in 0..<20 {
      storeItem(title: "item \(index)", ago: TimeInterval(index * 60), image: index == 5)
    }
    try await history.load()
    XCTAssertEqual(history.tallRowIndices, [5])

    history.add(newImageItem())

    XCTAssertEqual(history.tallRowIndices, [0, 6])
  }

  /// Delete row by row: the batch delete in `clearAll` can fail on items
  /// with relationships left behind by other suites.
  private func clearStore() throws {
    let context = Storage.shared.context
    try context.fetch(FetchDescriptor<HistoryItem>()).forEach(context.delete)
    try context.fetch(FetchDescriptor<HistoryItemContent>()).forEach(context.delete)
    context.processPendingChanges()
    try context.save()
  }

  private func loadHistory(count: Int) async throws {
    for index in 0..<count {
      storeItem(title: "item \(index)", ago: TimeInterval(index * 60))
    }
    try await history.load()
  }

  private func search(_ query: String) async throws {
    history.searchQuery = query
    // Search results are throttled.
    try await Task.sleep(for: .milliseconds(400))
  }

  @discardableResult
  private func storeItem(
    title: String, ago: TimeInterval, pin: String? = nil, image: Bool = false
  ) -> HistoryItem {
    let content = image
      ? HistoryItemContent(type: NSPasteboard.PasteboardType.png.rawValue, value: Self.pngData)
      : HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: title.data(using: .utf8))

    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [content]
    item.title = title
    item.pin = pin
    item.firstCopiedAt = Date(timeIntervalSinceNow: -ago)
    item.lastCopiedAt = Date(timeIntervalSinceNow: -ago)
    try? Storage.shared.context.save()
    return item
  }

  private func newItem(_ value: String) -> HistoryItem {
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: value.data(using: .utf8))
    ]
    item.title = item.generateTitle()
    return item
  }

  private func newImageItem() -> HistoryItem {
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    // A different type than the stored image, so it is not merged as a duplicate.
    item.contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: Self.pngData)
    ]
    return item
  }
}
