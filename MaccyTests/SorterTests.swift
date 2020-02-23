import XCTest
@testable import Maccy

class SorterTests: XCTestCase {
  let item1 = HistoryItem(value: "foo",
                          firstCopiedAt: Date(timeIntervalSinceNow: -300),
                          lastCopiedAt: Date(timeIntervalSinceNow: -100),
                          numberOfCopies: 3)
  let item2 = HistoryItem(value: "bar",
                          firstCopiedAt: Date(timeIntervalSinceNow: -400),
                          lastCopiedAt: Date(timeIntervalSinceNow: -300),
                          numberOfCopies: 2)
  let item3 = HistoryItem(value: "baz",
                          firstCopiedAt: Date(timeIntervalSinceNow: -200),
                          lastCopiedAt: Date(timeIntervalSinceNow: -200),
                          numberOfCopies: 1)

  func testSortByLastCopiedAt() {
    let sorter = Sorter(by: "lastCopiedAt")
    XCTAssertEqual(sorter.sort([item1, item2, item3]), [item2, item3, item1])
  }

  func testSortByFirstCopiedAt() {
    let sorter = Sorter(by: "firstCopiedAt")
    XCTAssertEqual(sorter.sort([item1, item2, item3]), [item2, item1, item3])
  }

  func testSortByNumberOfCopies() {
    let sorter = Sorter(by: "numberOfCopies")
    XCTAssertEqual(sorter.sort([item1, item2, item3]), [item3, item2, item1])
  }

  func testSortByPin() {
    item1.pin = "a"
    item3.pin = "b"
    let sorter = Sorter(by: "lastCopiedAt")
    XCTAssertEqual(sorter.sort([item1, item2, item3]), [item2, item3, item1])
  }
}
