import Defaults
import SwiftData
import XCTest
@testable import Maccy

/// Verifies that pinning an item survives a clear-unpinned operation, both in memory and in the committed store.
@MainActor
final class HistoryPinPersistenceTests: XCTestCase {
  private let history = History.shared
  private let savedSize = Defaults[.size]
  private let savedSortBy = Defaults[.sortBy]

  override func setUp() async throws {
    try await super.setUp()
    history.clearAll()
    AppState.shared.navigator.selectWithoutScrolling(item: nil)
    Defaults[.size] = 10
    Defaults[.sortBy] = .firstCopiedAt
  }

  override func tearDown() async throws {
    history.searchQuery = ""
    Defaults[.size] = savedSize
    Defaults[.sortBy] = savedSortBy
    try await super.tearDown()
  }

  /// A pinned item persists across `clear()` (which removes only unpinned items), and its pin value round-trips through the committed store.
  func testClearingUnpinnedAfterPinPersistsPinnedItem() {
    let pinned = history.add(historyItem("foo"))
    history.add(historyItem("bar"))

    history.togglePin(pinned)
    let pin = pinned.item.pin
    history.clear()

    XCTAssertEqual(history.items, [pinned])
    XCTAssertEqual(pinned.item.pin, pin)

    let stored = (try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())) ?? []
    XCTAssertEqual(stored.map(\.title), ["foo"])
    XCTAssertEqual(stored.first?.pin, pin)
  }

  /// Builds a single-string-content `HistoryItem` inserted into the shared context, with title derived from its content.
  private func historyItem(_ value: String) -> HistoryItem {
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.data(using: .utf8)
      )
    ]
    item.numberOfCopies = 1
    item.title = item.generateTitle()
    return item
  }
}
