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

  func testClearing() {
    history.add("foo")
    history.clear()
    XCTAssertEqual(history.all(), [])
  }

  func testMaxSize() {
    for i in 0...10 {
      history.add(String(i))
    }

    XCTAssertEqual(history.all().count, 10)
    XCTAssertTrue(history.all().contains("10"))
    XCTAssertFalse(history.all().contains("0"))
  }

  func testMaxSizeIsChanged() {
    for i in 0...10 {
      history.add(String(i))
    }
    UserDefaults.standard.set(5, forKey: "historySize")

    XCTAssertEqual(history.all().count, 5)
    XCTAssertTrue(history.all().contains("10"))
    XCTAssertFalse(history.all().contains("5"))
  }
}
