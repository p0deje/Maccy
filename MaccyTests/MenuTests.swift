import XCTest
@testable import Maccy

class MenuTests: XCTestCase {
  let clipboard = Clipboard.shared
  let history = History()

  let savedPasteByDefault = UserDefaults.standard.pasteByDefault
  let savedRemoveFormattingByDefault = UserDefaults.standard.removeFormattingByDefault

  var menu: Menu!
  var chunkedItems: [[HistoryMenuItem]] {
    return stride(from: 0, to: menu.historyMenuItems.count, by: 3).map({ index in
      Array(menu.historyMenuItems[index ..< Swift.min(index + 3, menu.historyMenuItems.count)])
    })
  }

  override func setUp() {
    CoreDataManager.inMemory = true
    history.clear()
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
    UserDefaults.standard.pasteByDefault = savedPasteByDefault
    UserDefaults.standard.removeFormattingByDefault = savedRemoveFormattingByDefault
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

  func testItemsWhenPasteAndRemoveFormattingAreOff() {
    UserDefaults.standard.pasteByDefault = false
    UserDefaults.standard.removeFormattingByDefault = false

    menu.buildItems()
    menu.prepareForPopup(location: .inMenuBar)

    XCTAssertEqual(chunkedItems.count, 3)
    for (index, chunk) in chunkedItems.enumerated() {
      XCTAssert(chunk[0] is HistoryMenuItem.CopyMenuItem)
      XCTAssert(chunk[1] is HistoryMenuItem.PasteMenuItem)
      XCTAssert(chunk[2] is HistoryMenuItem.PasteWithoutFormattingMenuItem)
      XCTAssertFalse(chunk[0].isAlternate)
      XCTAssertTrue(chunk[1].isAlternate)
      XCTAssertTrue(chunk[2].isAlternate)
      XCTAssertEqual(chunk[0].keyEquivalentModifierMask, .command)
      XCTAssertEqual(chunk[1].keyEquivalentModifierMask, .option)
      XCTAssertEqual(chunk[2].keyEquivalentModifierMask, NSEvent.ModifierFlags([.option, .shift]))
      for item in chunk {
        XCTAssertEqual(item.keyEquivalent, String(index + 1))
      }
    }
  }

  func testItemsWhenPasteIsOnAndRemoveFormattingIsOff() {
    UserDefaults.standard.pasteByDefault = true
    UserDefaults.standard.removeFormattingByDefault = false

    menu.buildItems()
    menu.prepareForPopup(location: .inMenuBar)

    XCTAssertEqual(chunkedItems.count, 3)
    for (index, chunk) in chunkedItems.enumerated() {
      XCTAssert(chunk[0] is HistoryMenuItem.PasteMenuItem)
      XCTAssert(chunk[1] is HistoryMenuItem.CopyMenuItem)
      XCTAssert(chunk[2] is HistoryMenuItem.PasteWithoutFormattingMenuItem)
      XCTAssertFalse(chunk[0].isAlternate)
      XCTAssertTrue(chunk[1].isAlternate)
      XCTAssertTrue(chunk[2].isAlternate)
      XCTAssertEqual(chunk[0].keyEquivalentModifierMask, .command)
      XCTAssertEqual(chunk[1].keyEquivalentModifierMask, .option)
      XCTAssertEqual(chunk[2].keyEquivalentModifierMask, NSEvent.ModifierFlags([.command, .shift]))
      for item in chunk {
        XCTAssertEqual(item.keyEquivalent, String(index + 1))
      }
    }
  }

  func testItemsWhenPasteIsOffAndRemoveFormattingIsOn() {
    UserDefaults.standard.pasteByDefault = false
    UserDefaults.standard.removeFormattingByDefault = true

    menu.buildItems()
    menu.prepareForPopup(location: .inMenuBar)

    XCTAssertEqual(chunkedItems.count, 3)
    for (index, chunk) in chunkedItems.enumerated() {
      XCTAssert(chunk[0] is HistoryMenuItem.CopyMenuItem)
      XCTAssert(chunk[1] is HistoryMenuItem.PasteMenuItem)
      XCTAssert(chunk[2] is HistoryMenuItem.PasteWithoutFormattingMenuItem)
      XCTAssertFalse(chunk[0].isAlternate)
      XCTAssertTrue(chunk[1].isAlternate)
      XCTAssertTrue(chunk[2].isAlternate)
      XCTAssertEqual(chunk[0].keyEquivalentModifierMask, .command)
      XCTAssertEqual(chunk[1].keyEquivalentModifierMask, NSEvent.ModifierFlags([.option, .shift]))
      XCTAssertEqual(chunk[2].keyEquivalentModifierMask, .option)
      for item in chunk {
        XCTAssertEqual(item.keyEquivalent, String(index + 1))
      }
    }
  }

  func testItemsWhenPasteIsOnAndRemoveFormattingIsOn() {
    UserDefaults.standard.pasteByDefault = true
    UserDefaults.standard.removeFormattingByDefault = true

    menu.buildItems()
    menu.prepareForPopup(location: .inMenuBar)

    XCTAssertEqual(chunkedItems.count, 3)
    for (index, chunk) in chunkedItems.enumerated() {
      XCTAssert(chunk[0] is HistoryMenuItem.PasteWithoutFormattingMenuItem)
      XCTAssert(chunk[1] is HistoryMenuItem.CopyMenuItem)
      XCTAssert(chunk[2] is HistoryMenuItem.PasteMenuItem)
      XCTAssertFalse(chunk[0].isAlternate)
      XCTAssertTrue(chunk[1].isAlternate)
      XCTAssertTrue(chunk[2].isAlternate)
      XCTAssertEqual(chunk[0].keyEquivalentModifierMask, .command)
      XCTAssertEqual(chunk[1].keyEquivalentModifierMask, .option)
      XCTAssertEqual(chunk[2].keyEquivalentModifierMask, NSEvent.ModifierFlags([.command, .shift]))
      for item in chunk {
        XCTAssertEqual(item.keyEquivalent, String(index + 1))
      }
    }
  }

  private func historyItem(_ value: String) -> HistoryItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                     value: value.data(using: .utf8)!)
    let item = HistoryItem(contents: [content])
    return item
  }
}
