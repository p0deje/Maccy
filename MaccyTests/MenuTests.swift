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
    XCTAssertEqual(menu.items, [menu.items[0], menuItems[0]])
  }

  func testSearchWithPartialMatch() {
    menu.updateFilter(filter: "ba")
    XCTAssertEqual(menu.items, [menu.items[0], menuItems[1], menuItems[2]])
  }

  func testSearchWithNoMatch() {
    menu.updateFilter(filter: "xyz")
    XCTAssertEqual(menu.items, [menu.items[0]])
  }

  func testSearchWithEmpty() {
    menu.updateFilter(filter: "")
   XCTAssertEqual(menu.items, [menu.items[0]] + menuItems)
  }

  func testSeparator() {
    let separator = NSMenuItem.separator()
    menu.addItem(separator)
    menu.updateFilter(filter: "xyz")
    XCTAssertTrue(menu.items.contains(separator))
  }

  func testSearchIsKept() {
    let search = menu.items[0]
    menu.updateFilter(filter: "foo")
    XCTAssertTrue(menu.items.contains(search))
  }
}
