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
    XCTAssertEqual(history.all(), [])
  }

  func testAdding() {
    history.add("foo")
    history.add("bar")
    XCTAssertEqual(history.all(), ["bar", "foo"])
  }

  func testAddingSame() {
    history.add("foo")
    history.add("bar")
    history.add("foo")
    XCTAssertEqual(history.all(), ["foo", "bar"])
  }

  func testAddingBlank() {
    history.add(" ")
    history.add("\n")
    history.add(" foo")
    history.add("\n bar")
    XCTAssertEqual(history.all(), ["\n bar", " foo"])
  }

  func testIgnore() {
    UserDefaults.standard.set(true, forKey: "ignoreEvents")
    history.add("foo")
    XCTAssertEqual(history.all(), [])
  }

  func testClearing() {
    history.add("foo")
    history.clear()
    XCTAssertEqual(history.all(), [])
  }

  func testMaxSize() {
    for index in 0...10 {
      history.add(String(index))
    }

    XCTAssertEqual(history.all().count, 10)
    XCTAssertTrue(history.all().contains("10"))
    XCTAssertFalse(history.all().contains("0"))
  }

  func testMaxSizeIsChanged() {
    for index in 0...10 {
      history.add(String(index))
    }
    UserDefaults.standard.size = 5

    XCTAssertEqual(history.all().count, 5)
    XCTAssertTrue(history.all().contains("10"))
    XCTAssertFalse(history.all().contains("5"))
  }

  func testRemoving() {
    history.add("foo")
    history.add("bar")
    history.remove("foo")
    XCTAssertEqual(history.all(), ["bar"])
  }

  func testRemovingRecent() {
    history.add("foo")
    history.add("bar")
    history.removeRecent()
    XCTAssertEqual(history.all(), ["foo"])
  }
}
