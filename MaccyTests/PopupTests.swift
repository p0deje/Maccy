import Defaults
import XCTest
@testable import Maccy

@MainActor
final class PopupTests: XCTestCase {
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

  func testOpenSelectsNewestHistoryItem() {
    let older = history.add(historyItem("bar"))
    let newest = history.add(historyItem("foo"))
    AppState.shared.navigator.select(item: older)

    AppState.shared.popup.open(height: 0)

    XCTAssertEqual(AppState.shared.navigator.selection.first, newest)
  }

  func testCappedListHeightLimitsRowsToMaxVisibleItems() {
    // Cap binds when content exceeds maxVisibleItems rows (10 rows × 22pt).
    XCTAssertEqual(
      Popup.cappedListHeight(contentHeight: 4_400, maxVisibleItems: 10, itemHeight: 22),
      220,
      accuracy: 0.001
    )
    // No cap when content already fits within the limit.
    XCTAssertEqual(
      Popup.cappedListHeight(contentHeight: 150, maxVisibleItems: 10, itemHeight: 22),
      150,
      accuracy: 0.001
    )
    // maxVisibleItems <= 0 means uncapped (defensive; not exposed in Settings).
    XCTAssertEqual(
      Popup.cappedListHeight(contentHeight: 4_400, maxVisibleItems: 0, itemHeight: 22),
      4_400,
      accuracy: 0.001
    )
    // Respects itemHeight (macOS 26+ uses 24pt per row).
    XCTAssertEqual(
      Popup.cappedListHeight(contentHeight: 4_400, maxVisibleItems: 10, itemHeight: 24),
      240,
      accuracy: 0.001
    )
  }

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
