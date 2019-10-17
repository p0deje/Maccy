import XCTest
@testable import Maccy

// Somehow highlighted item is always nil, so highlighting tests fail.
class MenuTests: XCTestCase {
  let clipboard = Clipboard()
  let history = History()
  let menuItems = ["foo", "bar", "baz"]

  var menu: Menu!

  override func setUp() {
    super.setUp()

    menu = Menu(history: history, clipboard: clipboard)
    menu.addItem(NSMenuItem(title: "Search", action: nil, keyEquivalent: ""))
    for menuItem in menuItems {
      menu.prepend(menuItem)
    }
  }

  func testSeparator() {
    menu.addItem(NSMenuItem.separator())
    menu.updateFilter(filter: "xyz")
    XCTAssertTrue(menu.items.contains(where: { $0.isSeparatorItem }))
  }

  func testSearchIsKept() {
    let search = menu.items[0]
    menu.updateFilter(filter: "foo")
    XCTAssertTrue(menu.items.contains(search))
  }
}
