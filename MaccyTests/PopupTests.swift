import Defaults
import XCTest
@testable import Maccy

@MainActor
final class PopupTests: XCTestCase {
  private let history = History.shared
  private let savedSize = Defaults[.size]
  private let savedSortBy = Defaults[.sortBy]

  override func setUp() {
    super.setUp()
    history.clearAll()
    AppState.shared.navigator.selectWithoutScrolling(item: nil)
    Defaults[.size] = 10
    Defaults[.sortBy] = .firstCopiedAt
  }

  override func tearDown() {
    history.searchQuery = ""
    Defaults[.size] = savedSize
    Defaults[.sortBy] = savedSortBy
    super.tearDown()
  }

  func testOpenSelectsNewestHistoryItem() {
    let older = history.add(historyItem("bar"))
    let newest = history.add(historyItem("foo"))
    AppState.shared.navigator.select(item: older)

    AppState.shared.popup.open(height: 0)

    XCTAssertEqual(AppState.shared.navigator.selection.first, newest)
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
