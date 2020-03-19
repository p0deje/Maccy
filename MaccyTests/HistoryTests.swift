import XCTest
@testable import Maccy

class HistoryTests: XCTestCase {
  let savedIgnoreEvents = UserDefaults.standard.ignoreEvents
  let savedSize = UserDefaults.standard.size
  let savedStorage = UserDefaults.standard.storage
  let history = History()

  override func setUp() {
    super.setUp()
    UserDefaults.standard.ignoreEvents = false
    UserDefaults.standard.size = 10
    UserDefaults.standard.storage = []
  }

  override func tearDown() {
    super.tearDown()
    UserDefaults.standard.ignoreEvents = savedIgnoreEvents
    UserDefaults.standard.size = savedSize
    UserDefaults.standard.storage = savedStorage
  }

  func testDefaultIsEmpty() {
    XCTAssertEqual(history.all, [])
  }

  func testAdding() {
    history.add(historyItem("foo"))
    history.add(historyItem("bar"))
    XCTAssertEqual(history.all, [historyItem("bar"), historyItem("foo")])
  }

  func testAddingSame() {
    history.add(historyItem("foo"))
    history.add(historyItem("bar"))
    history.add(historyItem("foo"))
    XCTAssertEqual(history.all, [historyItem("bar"), historyItem("foo")])
    XCTAssertTrue(history.all[1].lastCopiedAt > history.all[1].firstCopiedAt)
    XCTAssertEqual(history.all[1].numberOfCopies, 2)
  }

  func testAddingBlank() {
    history.add(historyItem(" "))
    history.add(historyItem("\n"))
    history.add(historyItem(" foo"))
    history.add(historyItem("\n bar"))
    XCTAssertEqual(history.all, [historyItem("\n bar"), historyItem(" foo")])
  }

  func testIgnore() {
    UserDefaults.standard.set(true, forKey: "ignoreEvents")
    history.add(historyItem("foo"))
    XCTAssertEqual(history.all, [])
  }

  func testUpdate() {
    history.add(historyItem("foo"))
    let historyItem = history.all[0]

    historyItem.numberOfCopies = 0
    XCTAssertEqual(history.all[0].numberOfCopies, 1)

    history.update(historyItem)
    XCTAssertEqual(history.all[0].numberOfCopies, 0)
  }

  func testClearing() {
    history.add(historyItem("foo"))
    history.clear()
    XCTAssertEqual(history.all, [])
  }

  func testMaxSize() {
    for index in 0...10 {
      history.add(historyItem(String(index)))
    }

    XCTAssertEqual(history.all.count, 10)
    XCTAssertTrue(history.all.contains(historyItem("10")))
    XCTAssertFalse(history.all.contains(historyItem("0")))
  }

  func testMaxSizeIsChanged() {
    for index in 0...10 {
      history.add(historyItem(String(index)))
    }
    UserDefaults.standard.size = 5

    XCTAssertEqual(history.all.count, 5)
    XCTAssertTrue(history.all.contains(historyItem("10")))
    XCTAssertFalse(history.all.contains(historyItem("5")))
  }

  func testRemoving() {
    history.add(historyItem("foo"))
    history.add(historyItem("bar"))
    history.remove(historyItem("foo"))
    XCTAssertEqual(history.all, [historyItem("bar")])
  }

  private func historyItem(_ value: String) -> HistoryItem {
    let item = HistoryItem(value: value.data(using: .utf8)!)
    item.types = [.string]
    return item
  }

  private func historyItem(_ value: NSImage) -> HistoryItem {
    let item = HistoryItem(value: value.tiffRepresentation!)
    item.types = [.tiff]
    return item
  }
}
