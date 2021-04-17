import XCTest
@testable import Maccy

class HistoryMenuItemTests: XCTestCase {
  let savedImageMaxHeight = UserDefaults.standard.imageMaxHeight

  var firstCopiedAt: Date! {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
    return formatter.date(from: "2020/07/10 12:31:34")
  }

  var lastCopiedAt: Date! {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
    return formatter.date(from: "2020/07/10 12:41:34")
  }

  override func setUp() {
    super.setUp()
    CoreDataManager.inMemory = true
    UserDefaults.standard.imageMaxHeight = 40
  }

  override func tearDown() {
    super.tearDown()
    CoreDataManager.inMemory = false
    UserDefaults.standard.imageMaxHeight = savedImageMaxHeight
  }

  func testString() {
    let title = "foo"
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, title)
    XCTAssertEqual(menuItem.value, title)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
    XCTAssertNil(menuItem.image)
  }

  func testTitleShorterThanMaxLength() {
    let title = String(repeating: "a", count: 49)
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, title)
    XCTAssertEqual(menuItem.value, title)
    XCTAssertEqual(menuItem.title.count, 49)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testTitleOfMaxLength() {
    let title = String(repeating: "a", count: 50)
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, title)
    XCTAssertEqual(menuItem.value, title)
    XCTAssertEqual(menuItem.title.count, 50)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testTitleLongerThanMaxLength() {
    let trimmedTitle = String(repeating: "a", count: 33) + "..." + String(repeating: "a", count: 17)
    let title = String(repeating: "a", count: 51)
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, trimmedTitle)
    XCTAssertEqual(menuItem.value, title)
    XCTAssertEqual(menuItem.title.count, 53)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testTitleWithWhitespaces() {
    let title = "   foo   "
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, "foo")
    XCTAssertEqual(menuItem.value, title)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testTitleWithNewlines() {
    let title = "\nfoo\nbar\n"
    let menuItem = historyMenuItem(title)
    XCTAssertEqual(menuItem.title, "foobar")
    XCTAssertEqual(menuItem.value, title)
    XCTAssertEqual(menuItem.toolTip, tooltip(title))
  }

  func testImage() {
    let image = NSImage(named: "NSBluetoothTemplate")!
    let menuItem = historyMenuItem(image)
    XCTAssertEqual(menuItem.title, "")
    XCTAssertEqual(menuItem.value, "")
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

  func testFile() {
    let url = URL(fileURLWithPath: "/tmp/foo.bar")
    let menuItem = historyMenuItem(url)
    XCTAssertEqual(menuItem.title, "file:///tmp/foo.bar")
    XCTAssertEqual(menuItem.value, "file:///tmp/foo.bar")
    XCTAssertEqual(menuItem.toolTip, tooltip("file:///tmp/foo.bar"))
    XCTAssertNil(menuItem.image)
  }

  func testFileWithEscapedChars() {
    let url = URL(fileURLWithPath: "/tmp/产品培训/产品培训.txt")
    let menuItem = historyMenuItem(url)
    XCTAssertEqual(menuItem.title, "file:///tmp/产品培训/产品培训.txt")
    XCTAssertEqual(menuItem.value, "file:///tmp/产品培训/产品培训.txt")
    XCTAssertEqual(menuItem.toolTip, tooltip("file:///tmp/产品培训/产品培训.txt"))
    XCTAssertNil(menuItem.image)
  }

  func testItemWithoutData() {
    let menuItem = historyMenuItem(nil)
    XCTAssertEqual(menuItem.title, "")
    XCTAssertEqual(menuItem.value, "")
    XCTAssertEqual(menuItem.toolTip, nil)
    XCTAssertNil(menuItem.image)
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

  func testTooltipLongerThanMax() {
    let menuItem = historyMenuItem(String(repeating: "a", count: 5_001))
    XCTAssertEqual(menuItem.toolTip,
            tooltip("\(String(repeating: "a", count: 3_333))...\(String(repeating: "a", count: 1_667))"))
  }

  private func historyMenuItem(_ value: String?) -> HistoryMenuItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                     value: value?.data(using: .utf8))
    let item = HistoryItem(contents: [content])
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2
    return HistoryMenuItem(item: item, clipboard: Clipboard())
  }

  private func historyMenuItem(_ value: NSImage) -> HistoryMenuItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue,
                                     value: value.tiffRepresentation!)
    let item = HistoryItem(contents: [content])
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2
    return HistoryMenuItem(item: item, clipboard: Clipboard())
  }

  private func historyMenuItem(_ value: URL) -> HistoryMenuItem {
    let fileURLContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.fileURL.rawValue,
      value: value.dataRepresentation
    )
    let fileNameContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.string.rawValue,
      value: value.lastPathComponent.data(using: .utf8)
    )
    let item = HistoryItem(contents: [fileURLContent, fileNameContent])
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2
    return HistoryMenuItem(item: item, clipboard: Clipboard())
  }

  private func tooltip(_ title: String?) -> String {
    if title == nil {
      return """
             First copy time: Jul 10, 12:31:34
             Last copy time: Jul 10, 12:41:34
             Number of copies: 2
             \n \n\n
             Press ⌥⌫ to delete.
             Press ⌥P to (un)pin.
             """
    } else {
      return """
             \(title!)
             \n \n\n
             First copy time: Jul 10, 12:31:34
             Last copy time: Jul 10, 12:41:34
             Number of copies: 2
             \n \n\n
             Press ⌥⌫ to delete.
             Press ⌥P to (un)pin.
             """
    }
  }
}
