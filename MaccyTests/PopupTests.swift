import XCTest
import Defaults
@testable import Maccy

class PopupTests: XCTestCase {
  let savedPasteByDefault = Defaults[.pasteByDefault]
  let savedShowSearch = Defaults[.showSearch]

  var popup: Popup!

  override func setUp() {
    super.setUp()
    popup = Popup()
  }

  override func tearDown() {
    super.tearDown()
    popup.deinitEventsMonitor()
    Defaults[.pasteByDefault] = savedPasteByDefault
    Defaults[.showSearch] = savedShowSearch
  }

  func testShouldAutoPasteWhenPasteByDefaultEnabledAndSearchHidden() {
    Defaults[.pasteByDefault] = true
    Defaults[.showSearch] = false
    XCTAssertTrue(popup.shouldSelectFirstRecordOnOpen)
  }

  func testShouldNotAutoPasteWhenPasteByDefaultDisabled() {
    Defaults[.pasteByDefault] = false
    Defaults[.showSearch] = false
    XCTAssertFalse(popup.shouldSelectFirstRecordOnOpen)
  }

  func testShouldNotAutoPasteWhenSearchVisible() {
    Defaults[.pasteByDefault] = true
    Defaults[.showSearch] = true
    XCTAssertFalse(popup.shouldSelectFirstRecordOnOpen)
  }

  func testShouldNotAutoPasteWhenBothDisabledAndSearchVisible() {
    Defaults[.pasteByDefault] = false
    Defaults[.showSearch] = true
    XCTAssertFalse(popup.shouldSelectFirstRecordOnOpen)
  }
}
