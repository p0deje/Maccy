import XCTest
@testable import Maccy

class MenuTests: XCTestCase {
  let clipboard = Clipboard()
  let history = History()

  var menu: Menu!

  override func setUp() {
    CoreDataManager.inMemory = true
    super.setUp()

    let historyItems: [HistoryItem] = [
      HistoryItem(contents: [HistoryItemContent(type: "", value: "foo".data(using: .utf8)!)]),
      HistoryItem(contents: [HistoryItemContent(type: "", value: "bar".data(using: .utf8)!)]),
      HistoryItem(contents: [HistoryItemContent(type: "", value: "baz".data(using: .utf8)!)])
    ]
    historyItems.forEach(history.add(_:))

    menu = Menu(history: history, clipboard: clipboard)
    menu.addItem(NSMenuItem(title: "Search", action: nil, keyEquivalent: ""))
  }

  override func tearDown() {
    super.tearDown()
    CoreDataManager.inMemory = false
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

  private func historyItem(_ value: String) -> HistoryItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                     value: value.data(using: .utf8)!)
    let item = HistoryItem(contents: [content])
    return item
  }
}
