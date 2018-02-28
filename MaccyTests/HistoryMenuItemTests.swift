import XCTest
@testable import Maccy

class HistoryMenuItemTests: XCTestCase {
  func testTitleShorterThanMaxLength() {
    let title = String(repeating: "a", count: 49)
    let menuItem = HistoryMenuItem(title: title, clipboard: Clipboard())
    XCTAssertEqual(menuItem.title, title)
    XCTAssertEqual(menuItem.title.count, 49)
  }
  
  func testTitleOfMaxLength() {
    let title = String(repeating: "a", count: 50)
    let menuItem = HistoryMenuItem(title: title, clipboard: Clipboard())
    XCTAssertEqual(menuItem.title, title)
    XCTAssertEqual(menuItem.title.count, 50)
  }
  
  func testTitleLongerThanMaxLength() {
    let title = String(repeating: "a", count: 51)
    let menuItem = HistoryMenuItem(title: title, clipboard: Clipboard())
    XCTAssertEqual(menuItem.title, "\(title)...")
    XCTAssertEqual(menuItem.title.count, 54)
  }
  
  func testTitleWithWhitespaces() {
    let title = "   foo   "
    let menuItem = HistoryMenuItem(title: title, clipboard: Clipboard())
    XCTAssertEqual(menuItem.title, "foo")
  }
  
  func testCopyingOfFullTitle() {
    let title = String(repeating: "a", count: 51)
    let menuItem = HistoryMenuItem(title: title, clipboard: Clipboard())
    menuItem.copy(menuItem)
    XCTAssertEqual(NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.string), title)
  }
}
