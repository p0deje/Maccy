import XCTest
@testable import Maccy

class SorterTests: XCTestCase {
  let savedPinTo = UserDefaults.standard.pinTo

  var item1: HistoryItem!
  var item2: HistoryItem!
  var item3: HistoryItem!

  override func setUp() {
    CoreDataManager.inMemory = true
    super.setUp()
    item1 = historyItem(value: "foo", firstCopiedAt: -300, lastCopiedAt: -100, numberOfCopies: 3)
    item2 = historyItem(value: "bar", firstCopiedAt: -400, lastCopiedAt: -300, numberOfCopies: 2)
    item3 = historyItem(value: "bar", firstCopiedAt: -200, lastCopiedAt: -200, numberOfCopies: 1)
  }

  override func tearDown() {
    super.tearDown()
    CoreDataManager.inMemory = false
    UserDefaults.standard.pinTo = savedPinTo
  }

  func testSortByLastCopiedAt() {
    let sorter = Sorter(by: "lastCopiedAt")
    XCTAssertEqual(sorter.sort([item1, item2, item3]), [item1, item3, item2])
  }

  func testSortByFirstCopiedAt() {
    let sorter = Sorter(by: "firstCopiedAt")
    XCTAssertEqual(sorter.sort([item1, item2, item3]), [item3, item1, item2])
  }

  func testSortByNumberOfCopies() {
    let sorter = Sorter(by: "numberOfCopies")
    XCTAssertEqual(sorter.sort([item1, item2, item3]), [item1, item2, item3])
  }

  func testSortByPinToTop() {
    UserDefaults.standard.pinTo = "top"

    item1.pin = "a"
    item3.pin = "b"
    let sorter = Sorter(by: "lastCopiedAt")
    XCTAssertEqual(sorter.sort([item1, item2, item3]), [item1, item3, item2])
  }

  func testSortByPinToBottom() {
    UserDefaults.standard.pinTo = "bottom"

    item1.pin = "a"
    item3.pin = "b"
    let sorter = Sorter(by: "lastCopiedAt")
    XCTAssertEqual(sorter.sort([item1, item2, item3]), [item2, item1, item3])
  }

  private func historyItem(value: String, firstCopiedAt: Int,
                           lastCopiedAt: Int, numberOfCopies: Int) -> HistoryItem {
    let content = HistoryItemContent(type: "", value: value.data(using: .utf8)!)
    let item = HistoryItem(contents: [content])
    item.firstCopiedAt = Date(timeIntervalSinceNow: TimeInterval(firstCopiedAt))
    item.lastCopiedAt = Date(timeIntervalSinceNow: TimeInterval(lastCopiedAt))
    item.numberOfCopies = numberOfCopies
    return item
  }
}
