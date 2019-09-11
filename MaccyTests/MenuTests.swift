import XCTest
@testable import Maccy

// Somehow highlighted item is always nil, so highlighting tests fail.
class MenuTests: XCTestCase {
  let clipboard = Clipboard()
  var menu: Menu!

  lazy var menuItems: [HistoryMenuItem] = [
    HistoryMenuItem(title: "foo", onSelected: { _ in }),
    HistoryMenuItem(title: "bar", onSelected: { _ in }),
    HistoryMenuItem(title: "baz", onSelected: { _ in })
  ]

  override func setUp() {
    super.setUp()

    menu = Menu()
    menu.addSearchItem()
    for menuItem in menuItems {
      menu.addItem(menuItem)
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
