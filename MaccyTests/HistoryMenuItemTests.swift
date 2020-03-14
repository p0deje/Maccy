import XCTest
@testable import Maccy

class HistoryMenuItemTests: XCTestCase {
  let savedImageMaxHeight = UserDefaults.standard.imageMaxHeight

  override func setUp() {
    super.setUp()
    UserDefaults.standard.imageMaxHeight = 40
  }

  override func tearDown() {
    super.tearDown()
    UserDefaults.standard.imageMaxHeight = savedImageMaxHeight
  }

  func testString() {
    let title = "foo"
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, title)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
    XCTAssertNil(menuItem.image)
  }

  func testTitleShorterThanMaxLength() {
    let title = String(repeating: "a", count: 49)
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, title)
    XCTAssertEqual(menuItem.title.count, 49)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testTitleOfMaxLength() {
    let title = String(repeating: "a", count: 50)
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, title)
    XCTAssertEqual(menuItem.title.count, 50)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testTitleLongerThanMaxLength() {
    let title = String(repeating: "a", count: 51)
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, "\(title)...")
    XCTAssertEqual(menuItem.title.count, 54)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testTitleWithWhitespaces() {
    let title = "   foo   "
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, "foo")
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testImage() {
    let image = NSImage(named: "NSBluetoothTemplate")!
    let menuItem = historyMenuItem(image)
    XCTAssertEqual(menuItem.title, "")
    XCTAssertEqual(menuItem.toolTip, tooltip(nil))
    XCTAssertNotNil(menuItem.image)
    XCTAssertEqual(menuItem.image!.size, image.size)
  }

  // We also need to add test for image with width bigger than max width.
  func testImageWithHeightBiggerThanMaxHeight() {
    let image = NSImage(named: "NSApplicationIcon")!
    let menuItem = historyMenuItem(image)
    XCTAssertEqual(menuItem.image!.size, NSSize(width: 40, height: 40))
  }

  func testUnpinnedByDefault() {
    let menuItem = historyMenuItem("foo")
    XCTAssertNil(menuItem.item.pin)
    XCTAssertFalse(menuItem.isPinned)
    XCTAssertNotEqual(menuItem.state, .on)
  }

  func testPin() {
    let menuItem = historyMenuItem("foo")
    menuItem.pin("a")
    XCTAssertEqual(menuItem.item.pin, "a")
    XCTAssertTrue(menuItem.isPinned)
    XCTAssertEqual(menuItem.state, .on)
  }

  func testUnpin() {
    let menuItem = historyMenuItem("foo")
    menuItem.pin("a")
    menuItem.unpin()
    XCTAssertNil(menuItem.item.pin)
    XCTAssertFalse(menuItem.isPinned)
    XCTAssertNotEqual(menuItem.state, .on)
  }

  private func historyMenuItem(_ value: String) -> HistoryMenuItem {
    let item = HistoryItem(value: value.data(using: .utf8)!)
    item.type = .string
    return HistoryMenuItem(item: item, onSelected: { _ in })
  }

  private func historyMenuItem(_ value: NSImage) -> HistoryMenuItem {
    let item = HistoryItem(value: value.tiffRepresentation!)
    item.type = .image
    return HistoryMenuItem(item: item, onSelected: { _ in })
  }

  private func tooltip(_ title: String?) -> String {
    if title == nil {
      return """
             Press ⌥+⌫ to delete.
             Press ⌥+p to (un)pin.
             """
    } else {
      return """
             \(title!)\n \n
             Press ⌥+⌫ to delete.
             Press ⌥+p to (un)pin.
             """
    }
  }
}
