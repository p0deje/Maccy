import XCTest
import Defaults
@testable import Maccy

class SorterTests: XCTestCase {
  let savedPinTo = Defaults[.pinTo]
  let sorter = Sorter()

  var item1: HistoryItem!
  var item2: HistoryItem!
  var item3: HistoryItem!

  @MainActor
  override func setUp() {
    super.setUp()
    item1 = historyItem(value: "foo", firstCopiedAt: -300, lastCopiedAt: -100, numberOfCopies: 3)
    item2 = historyItem(value: "bar", firstCopiedAt: -400, lastCopiedAt: -300, numberOfCopies: 2)
    item3 = historyItem(value: "bar", firstCopiedAt: -200, lastCopiedAt: -200, numberOfCopies: 1)
  }

  override func tearDown() {
    super.tearDown()
    Defaults[.pinTo] = savedPinTo
  }

  func testSortByLastCopiedAt() {
    XCTAssertEqual(sorter.sort([item1, item2, item3], by: .lastCopiedAt), [item1, item3, item2])
  }

  func testSortByFirstCopiedAt() {
    XCTAssertEqual(sorter.sort([item1, item2, item3], by: .firstCopiedAt), [item3, item1, item2])
  }

  func testSortByNumberOfCopies() {
    XCTAssertEqual(sorter.sort([item1, item2, item3], by: .numberOfCopies), [item1, item2, item3])
  }

  func testSortByPinToTop() {
    Defaults[.pinTo] = .top

    item1.pin = "a"
    item3.pin = "b"
    XCTAssertEqual(sorter.sort([item1, item2, item3], by: .lastCopiedAt), [item1, item3, item2])
  }

  func testSortByPinToBottom() {
    Defaults[.pinTo] = .bottom

    item1.pin = "a"
    item3.pin = "b"
    XCTAssertEqual(sorter.sort([item1, item2, item3], by: .lastCopiedAt), [item2, item1, item3])
  }

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
