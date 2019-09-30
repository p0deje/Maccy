import XCTest
@testable import Maccy

class HistoryTests: XCTestCase {
  let savedHistory = UserDefaults.standard.array(forKey: "history")
  let historySize = UserDefaults.standard.integer(forKey: "historySize")

  let history = History()

  override func setUp() {
    super.setUp()
    UserDefaults.standard.set([], forKey: "history")
    UserDefaults.standard.set(10, forKey: "historySize")
  }

  override func tearDown() {
    super.tearDown()
    UserDefaults.standard.set(savedHistory, forKey: "history")
    UserDefaults.standard.set(historySize, forKey: "historySize")
    UserDefaults.standard.set(false, forKey: "ignoreEvents")
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
    UserDefaults.standard.set(5, forKey: "historySize")

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
