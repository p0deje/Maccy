import XCTest
@testable import Maccy

class HistoryMenuItemTests: XCTestCase {
  func testTitleShorterThanMaxLength() {
    let title = String(repeating: "a", count: 49)
    let menuItem = HistoryMenuItem(item: HistoryItem(value: title), onSelected: { _ in })
    XCTAssertEqual(menuItem.title, title)
    XCTAssertEqual(menuItem.title.count, 49)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testTitleOfMaxLength() {
    let title = String(repeating: "a", count: 50)
    let menuItem = HistoryMenuItem(item: HistoryItem(value: title), onSelected: { _ in })
    XCTAssertEqual(menuItem.title, title)
    XCTAssertEqual(menuItem.title.count, 50)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testTitleLongerThanMaxLength() {
    let title = String(repeating: "a", count: 51)
    let menuItem = HistoryMenuItem(item: HistoryItem(value: title), onSelected: { _ in })
    XCTAssertEqual(menuItem.title, "\(title)...")
    XCTAssertEqual(menuItem.title.count, 54)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testTitleWithWhitespaces() {
    let title = "   foo   "
    let menuItem = HistoryMenuItem(item: HistoryItem(value: title), onSelected: { _ in })
    XCTAssertEqual(menuItem.title, "foo")
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testUnpinnedByDefault() {
    let menuItem = HistoryMenuItem(item: HistoryItem(value: "foo"), onSelected: { _ in })
    XCTAssertNil(menuItem.item.pin)
    XCTAssertFalse(menuItem.isPinned)
    XCTAssertNotEqual(menuItem.state, .on)
  }

  func testPin() {
    let menuItem = HistoryMenuItem(item: HistoryItem(value: "foo"), onSelected: { _ in })
    menuItem.pin("a")
    XCTAssertEqual(menuItem.item.pin, "a")
    XCTAssertTrue(menuItem.isPinned)
    XCTAssertEqual(menuItem.state, .on)
  }

  func testUnpin() {
    let menuItem = HistoryMenuItem(item: HistoryItem(value: "foo"), onSelected: { _ in })
    menuItem.pin("a")
    menuItem.unpin()
    XCTAssertNil(menuItem.item.pin)
    XCTAssertFalse(menuItem.isPinned)
    XCTAssertNotEqual(menuItem.state, .on)
  }

  private func tooltip(_ title: String) -> String {
    return """
           \(title)\n \n
           Press ⌥+⌫ to delete.
           Press ⌥+p to (un)pin.
           """
  }
}
