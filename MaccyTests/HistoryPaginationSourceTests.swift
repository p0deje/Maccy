import AppKit
import Defaults
import XCTest
@testable import Maccy

/// Exercises the SwiftData-backed pagination source against the in-memory
/// test store, with the item mix of a real history: text, images, and pins.
@MainActor
class HistoryPaginationSourceTests: XCTestCase {
  let savedSortBy = Defaults[.sortBy]
  var source: HistoryPaginationSource!

  // A valid 1x1 transparent PNG.
  static let pngData = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
  )!

  override func setUp() {
    super.setUp()
    Defaults[.sortBy] = .lastCopiedAt
    source = HistoryPaginationSource()
    clearStore()
  }

  override func tearDown() {
    super.tearDown()
    clearStore()
    Defaults[.sortBy] = savedSortBy
  }

  private func clearStore() {
    try? Storage.shared.context.delete(model: HistoryItem.self)
    try? Storage.shared.context.delete(model: HistoryItemContent.self)
    try? Storage.shared.context.save()
  }

  @discardableResult
  private func insertItem(
    title: String, ago: TimeInterval, pin: String? = nil, image: Bool = false
  ) -> HistoryItem {
    let content: HistoryItemContent
    if image {
      content = HistoryItemContent(
        type: NSPasteboard.PasteboardType.png.rawValue,
        value: Self.pngData
      )
    } else {
      content = HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: title.data(using: .utf8)
      )
    }

    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [content]
    item.numberOfCopies = 1
    item.title = title
    item.pin = pin
    item.firstCopiedAt = Date(timeIntervalSinceNow: -ago)
    item.lastCopiedAt = Date(timeIntervalSinceNow: -ago)
    return item
  }

  func testCountsOnlyUnpinnedItems() throws {
    for index in 0..<20 {
      insertItem(title: "item \(index)", ago: TimeInterval(index))
    }
    insertItem(title: "pinned", ago: 100, pin: "a")

    XCTAssertEqual(try source.count(), 20)
  }

  func testFetchReturnsPagesInSortOrder() throws {
    for index in 0..<250 {
      insertItem(title: "item \(index)", ago: TimeInterval(index * 60))
    }
    XCTAssertEqual(try source.count(), 250)

    let firstPage = try source.fetch(offset: 0, limit: 100)
    XCTAssertEqual(firstPage.count, 100)
    XCTAssertEqual(firstPage.first?.title, "item 0")
    XCTAssertEqual(firstPage.last?.title, "item 99")

    let lastPage = try source.fetch(offset: 200, limit: 100)
    XCTAssertEqual(lastPage.count, 50)
    XCTAssertEqual(lastPage.last?.title, "item 249")
  }

  /// Regression test: paging must not rely on SwiftData's `fetchOffset`,
  /// which can be ignored and then returns the first rows for every page.
  func testConsecutivePagesDoNotRepeat() throws {
    for index in 0..<250 {
      insertItem(title: "item \(index)", ago: TimeInterval(index * 60))
    }
    _ = try source.count()

    let firstPage = try source.fetch(offset: 0, limit: 100)
    let secondPage = try source.fetch(offset: 100, limit: 100)
    XCTAssertEqual(secondPage.first?.title, "item 100")
    XCTAssertEqual(secondPage.last?.title, "item 199")
    XCTAssertTrue(Set(firstPage.map(\.id)).isDisjoint(with: secondPage.map(\.id)))
  }

  func testFetchExcludesPinnedItems() throws {
    for index in 0..<10 {
      insertItem(title: "item \(index)", ago: TimeInterval(index * 60))
    }
    insertItem(title: "pinned", ago: 150, pin: "a")
    XCTAssertEqual(try source.count(), 10)

    let page = try source.fetch(offset: 0, limit: 100)
    XCTAssertEqual(page.count, 10)
    XCTAssertFalse(page.contains { $0.title == "pinned" })
  }

  func testTallRowIndicesForImageItems() throws {
    for index in 0..<30 {
      insertItem(title: "item \(index)", ago: TimeInterval(index * 60), image: index == 5 || index == 17)
    }
    _ = try source.count()

    XCTAssertEqual(try source.tallRowIndices(), [5, 17])
  }

  func testTallRowIndicesWithoutImages() throws {
    for index in 0..<10 {
      insertItem(title: "item \(index)", ago: TimeInterval(index * 60))
    }
    _ = try source.count()

    XCTAssertEqual(try source.tallRowIndices(), [])
  }

  func testManagerLoadsLargeHistory() throws {
    for index in 0..<650 {
      insertItem(title: "item \(index)", ago: TimeInterval(index * 60), image: index % 100 == 7)
    }
    insertItem(title: "pinned", ago: 30, pin: "a")

    let manager = PaginationManager(source: source)
    try manager.load()

    XCTAssertEqual(manager.totalCount, 650)
    XCTAssertEqual(manager.loadedRange, 0..<200)
    XCTAssertEqual(manager.loadedItems.first?.title, "item 0")
    XCTAssertEqual(manager.tallRowIndices, [7, 107, 207, 307, 407, 507, 607])

    try manager.ensureRowsLoaded(600..<650)
    // Rows 600..<650 need page 6; with one page of lookahead the window
    // covers pages 5-6, i.e. rows 500..<650.
    XCTAssertEqual(manager.loadedRange, 500..<650)
    XCTAssertEqual(manager.loadedItems.last?.title, "item 649")
  }
}
