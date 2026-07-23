import XCTest
import Defaults
@testable import Maccy

class SorterTests: XCTestCase {
  let savedPinOrder = Defaults[.pinOrder]
  let savedPinSortBy = Defaults[.pinSortBy]
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
    Defaults[.pinOrder] = PinOrder()
    Defaults[.pinSortBy] = .custom
  }

  override func tearDown() {
    super.tearDown()
    Defaults[.pinOrder] = savedPinOrder
    Defaults[.pinSortBy] = savedPinSortBy
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

  func testSortPinsByLastCopiedAt() {
    pinItems()

    XCTAssertEqual(sorter.sortPins([item2, item3, item1], by: .lastCopiedAt), [item1, item3, item2])
  }

  func testSortPinsByFirstCopiedAt() {
    pinItems()

    XCTAssertEqual(sorter.sortPins([item2, item3, item1], by: .firstCopiedAt), [item3, item1, item2])
  }

  func testSortPinsByNumberOfCopies() {
    pinItems()

    XCTAssertEqual(sorter.sortPins([item2, item3, item1], by: .numberOfCopies), [item1, item2, item3])
  }

  func testSortPinsByPinLetter() {
    pinItems()

    XCTAssertEqual(sorter.sortPins([item2, item3, item1], by: .pinLetter), [item1, item3, item2])
  }

  func testSortPinsByCustomOrder() {
    pinItems()
    Defaults[.pinOrder] = PinOrder(pins: ["c", "a", "b"])

    XCTAssertEqual(sorter.sortPins([item1, item2, item3], by: .custom), [item2, item1, item3])
  }

  func testCustomPinSortAppendsPinsMissingFromOrder() {
    pinItems()
    Defaults[.pinOrder] = PinOrder(pins: ["b"])

    XCTAssertEqual(sorter.sortPins([item3, item2, item1], by: .custom), [item3, item2, item1])
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

  private func pinItems() {
    item1.pin = "a"
    item2.pin = "c"
    item3.pin = "b"
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

@MainActor
class PinManagerTests: XCTestCase {
  let savedPinOrder = Defaults[.pinOrder]
  let savedPinSortBy = Defaults[.pinSortBy]

  override func setUp() {
    super.setUp()
    Defaults[.pinOrder] = PinOrder()
    Defaults[.pinSortBy] = .custom
  }

  override func tearDown() {
    super.tearDown()
    Defaults[.pinOrder] = savedPinOrder
    Defaults[.pinSortBy] = savedPinSortBy
  }

  func testMovingPinsIsDisabledForAutomaticSorting() {
    let manager = pinManager()
    Defaults[.pinSortBy] = .pinLetter
    let originalPins = manager.pinnedItems
    let originalOrder = Defaults[.pinOrder]

    manager.move(from: IndexSet(integer: 0), to: 3)

    XCTAssertEqual(manager.pinnedItems, originalPins)
    XCTAssertEqual(Defaults[.pinOrder], originalOrder)
  }

  func testAutomaticSortingCanBeUsedAsCustomOrder() {
    let manager = pinManager()

    manager.adoptSortingForCustomOrder(.pinLetter)

    XCTAssertEqual(Defaults[.pinOrder].pins, ["a", "b", "c"])
  }

  func testAutomaticSortingWouldChangeDifferentCustomOrder() {
    let manager = pinManager()

    XCTAssertTrue(manager.sortingWouldChangeCurrentOrder(.pinLetter))
  }

  func testAutomaticSortingWouldNotChangeMatchingCustomOrder() {
    let manager = pinManager(pins: ["a", "b", "c"])

    XCTAssertFalse(manager.sortingWouldChangeCurrentOrder(.pinLetter))
  }

  private func pinManager(pins: [String] = ["c", "a", "b"]) -> PinManager {
    let items = pins.map { pin in
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.pin = pin
      return HistoryItemDecorator(item)
    }
    let manager = PinManager()
    manager.load(from: items)
    return manager
  }
}
