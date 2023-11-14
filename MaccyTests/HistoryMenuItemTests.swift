import XCTest
@testable import Maccy

class HistoryMenuItemTests: XCTestCase {
  let boldFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
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
    XCTAssertNil(menuItem.image)
  }

  func testRTF() {
    let rtf = NSAttributedString(string: "foo").rtf(
      from: NSRange(0...2),
      documentAttributes: [:]
    )
    let menuItem = historyMenuItem(rtf, .rtf)
    XCTAssertEqual(menuItem.title, "foo")
    XCTAssertEqual(menuItem.value, "foo")
    XCTAssertNil(menuItem.image)
  }

  func testHTML() {
    let html = "<a href='#'>foo</a>".data(using: .utf8)
    let menuItem = historyMenuItem(html, .html)
    XCTAssertEqual(menuItem.title, "foo")
    XCTAssertEqual(menuItem.value, "foo")
    XCTAssertNil(menuItem.image)
  }

  func testImage() {
    let image = NSImage(named: "StatusBarMenuImage")!
    let menuItem = historyMenuItem(image)
    XCTAssertEqual(menuItem.title, " ")
    XCTAssertEqual(menuItem.value, "")
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
    XCTAssertNil(menuItem.image)
  }

  func testFileWithEscapedChars() {
    let url = URL(fileURLWithPath: "/tmp/产品培训/产品培训.txt")
    let menuItem = historyMenuItem(url)
    XCTAssertEqual(menuItem.title, "file:///tmp/产品培训/产品培训.txt")
    XCTAssertEqual(menuItem.value, "file:///tmp/产品培训/产品培训.txt")
    XCTAssertNil(menuItem.image)
  }

  func testItemWithoutData() {
    let menuItem = historyMenuItem(nil)
    XCTAssertEqual(menuItem.title, "")
    XCTAssertEqual(menuItem.value, "")
    XCTAssertNil(menuItem.image)
  }

  func testUnpinnedByDefault() {
    let menuItem = historyMenuItem("foo")
    XCTAssertNil(menuItem.item?.pin)
    XCTAssertFalse(menuItem.isPinned)
    XCTAssertNotEqual(menuItem.state, .on)
  }

  func testPin() {
    let menuItem = historyMenuItem("foo")
    menuItem.pin("a")
    XCTAssertEqual(menuItem.item?.pin, "a")
    XCTAssertTrue(menuItem.isPinned)
    XCTAssertEqual(menuItem.state, .on)
  }

  func testUnpin() {
    let menuItem = historyMenuItem("foo")
    menuItem.pin("a")
    menuItem.unpin()
    XCTAssertNil(menuItem.item?.pin)
    XCTAssertFalse(menuItem.isPinned)
    XCTAssertNotEqual(menuItem.state, .on)
  }

  func testHighlight() {
    let menuItem = historyMenuItem("foo bar baz")
    menuItem.highlight([4...6, 8...9])
    let expectedTitle = NSMutableAttributedString(string: "foo bar baz")
    expectedTitle.addAttribute(.font, value: boldFont, range: NSRange(location: 4, length: 3))
    expectedTitle.addAttribute(.font, value: boldFont, range: NSRange(location: 8, length: 2))
    XCTAssertEqual(menuItem.attributedTitle, expectedTitle)
    menuItem.highlight([])
    XCTAssertEqual(menuItem.attributedTitle, nil)
  }

  func testHighlightInvalidRange() {
    let menuItem = historyMenuItem("")
    menuItem.highlight([0...0])
    XCTAssertEqual(menuItem.attributedTitle?.string, "")
  }

  private func historyMenuItem(_ value: String?, application: String? = "com.apple.finder") -> HistoryMenuItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                     value: value?.data(using: .utf8))
    let item = HistoryItem(contents: [content])
    item.application = application
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2
    return HistoryMenuItem(item: item, clipboard: Clipboard.shared)
  }

  private func historyMenuItem(_ value: Data?, _ type: NSPasteboard.PasteboardType) -> HistoryMenuItem {
    let content = HistoryItemContent(type: type.rawValue,
                                     value: value)
    let item = HistoryItem(contents: [content])
    item.application = "com.apple.finder"
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2
    return HistoryMenuItem(item: item, clipboard: Clipboard.shared)
  }

  private func historyMenuItem(_ value: NSImage) -> HistoryMenuItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue,
                                     value: value.tiffRepresentation!)
    let item = HistoryItem(contents: [content])
    item.application = "com.apple.finder"
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2
    return HistoryMenuItem(item: item, clipboard: Clipboard.shared)
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
    item.application = "com.apple.finder"
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = 2
    return HistoryMenuItem(item: item, clipboard: Clipboard.shared)
  }
}
