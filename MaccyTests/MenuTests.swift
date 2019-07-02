import XCTest
@testable import Maccy

// Somehow highlighted item is always nil, so highlighting tests fail.
class MenuTests: XCTestCase {
  let clipboard = Clipboard()
  var menu: Menu!

  lazy var menuItems: [HistoryMenuItem] = [
    HistoryMenuItem(title: "foo", hotKey: "", onSelected: { _ in }),
    HistoryMenuItem(title: "bar", hotKey: "", onSelected: { _ in }),
    HistoryMenuItem(title: "baz", hotKey: "", onSelected: { _ in })
  ]

  override func setUp() {
    super.setUp()

    menu = Menu()
    menu.addSearchItem()
    for menuItem in menuItems {
      menu.addItem(menuItem)
    }
  }

  func testSearchWithExactMatch() {
    menu.updateFilter(filter: "foo")
    XCTAssertEqual(menuItems[0].isHidden, false)
    XCTAssertEqual(menuItems[1].isHidden, true)
    XCTAssertEqual(menuItems[2].isHidden, true)
  }

  func testSearchWithPartialMatch() {
    menu.updateFilter(filter: "ba")
    XCTAssertEqual(menuItems[0].isHidden, true)
    XCTAssertEqual(menuItems[1].isHidden, false)
    XCTAssertEqual(menuItems[2].isHidden, false)
  }

  func testSearchWithNoMatch() {
    menu.updateFilter(filter: "xyz")
    XCTAssertEqual(menuItems[0].isHidden, true)
    XCTAssertEqual(menuItems[1].isHidden, true)
    XCTAssertEqual(menuItems[2].isHidden, true)
  }

  func testSearchWithEmpty() {
    menu.updateFilter(filter: "")
    XCTAssertEqual(menuItems[0].isHidden, false)
    XCTAssertEqual(menuItems[1].isHidden, false)
    XCTAssertEqual(menuItems[2].isHidden, false)
  }

  func testSeparator() {
    let separator = NSMenuItem.separator()
    menu.addItem(separator)
    menu.updateFilter(filter: "xyz")
    XCTAssertEqual(separator.isHidden, false)
  }

  func testDisabledItem() {
    menuItems[0].isEnabled = false
    menu.updateFilter(filter: "foo")
    XCTAssertEqual(menuItems[0].isHidden, true)
  }
}
