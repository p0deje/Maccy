import XCTest
import Defaults
@testable import Maccy

/// Tests for `Sorter.sort`, covering each sort key and pinned-item placement.
@MainActor
class SorterTests: XCTestCase {
  let savedPinTo = Defaults[.pinTo]
  let sorter = Sorter()

  var item1: HistoryItem!
  var item2: HistoryItem!
  var item3: HistoryItem!

  override func setUp() async throws {
    try await super.setUp()
    item1 = historyItem(value: "foo", firstCopiedAt: -300, lastCopiedAt: -100, numberOfCopies: 3)
    item2 = historyItem(value: "bar", firstCopiedAt: -400, lastCopiedAt: -300, numberOfCopies: 2)
    item3 = historyItem(value: "bar", firstCopiedAt: -200, lastCopiedAt: -200, numberOfCopies: 1)
  }

  override func tearDown() async throws {
    try await super.tearDown()
    Defaults[.pinTo] = savedPinTo
  }

  /// Sorting by last-copied time orders most-recent first.
  func testSortByLastCopiedAt() {
    XCTAssertEqual(sorter.sort([item1, item2, item3], by: .lastCopiedAt), [item1, item3, item2])
  }

  /// Sorting by first-copied time orders most-recent first.
  func testSortByFirstCopiedAt() {
    XCTAssertEqual(sorter.sort([item1, item2, item3], by: .firstCopiedAt), [item3, item1, item2])
  }

  /// Sorting by copy count orders most-copied first.
  func testSortByNumberOfCopies() {
    XCTAssertEqual(sorter.sort([item1, item2, item3], by: .numberOfCopies), [item1, item2, item3])
  }

  /// With pins placed at the top, pinned items precede unpinned ones.
  func testSortByPinToTop() {
    Defaults[.pinTo] = .top

    item1.pin = "a"
    item3.pin = "b"
    XCTAssertEqual(sorter.sort([item1, item2, item3], by: .lastCopiedAt), [item1, item3, item2])
  }

  /// With pins placed at the bottom, unpinned items precede pinned ones.
  func testSortByPinToBottom() {
    Defaults[.pinTo] = .bottom

    item1.pin = "a"
    item3.pin = "b"
    XCTAssertEqual(sorter.sort([item1, item2, item3], by: .lastCopiedAt), [item2, item1, item3])
  }

  /// Builds a `HistoryItem` with the given content and timing, inserted into the
  /// shared context.
  @MainActor
  private func historyItem(
    value: String,
    firstCopiedAt: Int,
    lastCopiedAt: Int,
    numberOfCopies: Int
  ) -> HistoryItem {
    let contents = [HistoryItemContent(type: "", value: value.data(using: .utf8)!)]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.firstCopiedAt = Date(timeIntervalSinceNow: TimeInterval(firstCopiedAt))
    item.lastCopiedAt = Date(timeIntervalSinceNow: TimeInterval(lastCopiedAt))
    item.numberOfCopies = numberOfCopies
    return item
  }
}
