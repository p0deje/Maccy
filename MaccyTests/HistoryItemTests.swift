import XCTest
@testable import Maccy

// swiftlint:disable force_try
class HistoryItemTests: XCTestCase {
  let savedIgnoredApps = UserDefaults.standard.ignoredApps
  let savedMaxMenuItemLength = UserDefaults.standard.maxMenuItemLength

  override func setUp() {
    CoreDataManager.inMemory = true
    UserDefaults.standard.maxMenuItemLength = 50
    super.setUp()
  }

  override func tearDown() {
    super.tearDown()
    CoreDataManager.shared.viewContext.reset()
    CoreDataManager.inMemory = false
    UserDefaults.standard.maxMenuItemLength = savedMaxMenuItemLength
  }

  func testTitleForString() {
    let title = "foo"
    let item = historyItem(title)
    XCTAssertEqual(item.title, title)
  }

  func testTitleShorterThanMaxLength() {
    let title = String(repeating: "a", count: 49)
    let item = historyItem(title)
    XCTAssertEqual(item.title, title)
    XCTAssertEqual(item.title?.count, 49)
  }

  func testTitleOfMaxLength() {
    let title = String(repeating: "a", count: 50)
    let item = historyItem(title)
    XCTAssertEqual(item.title, title)
    XCTAssertEqual(item.title?.count, 50)
  }

  func testTitleLongerThanMaxLength() {
    let trimmedTitle = String(repeating: "a", count: 33) + "..." + String(repeating: "a", count: 17)
    let title = String(repeating: "a", count: 51)
    let item = historyItem(title)
    XCTAssertEqual(item.title, trimmedTitle)
    XCTAssertEqual(item.title?.count, 53)
  }

  func testTitleWithWhitespaces() {
    let title = "   foo bar   "
    let item = historyItem(title)
    XCTAssertEqual(item.title, "···foo bar···")
  }

  func testTitleWithNewlines() {
    let title = "\nfoo\nbar\n"
    let item = historyItem(title)
    XCTAssertEqual(item.title, "⏎foo⏎bar⏎")
  }

  func testTitleWithTabs() {
    let title = "\tfoo\tbar\t"
    let item = historyItem(title)
    XCTAssertEqual(item.title, "⇥foo⇥bar⇥")
  }

  func testTitleWithRTF() {
    let rtf = NSAttributedString(string: "foo").rtf(
      from: NSRange(0...2),
      documentAttributes: [:]
    )
    let item = historyItem(rtf, .rtf)
    XCTAssertEqual(item.title, "foo")
  }

  func testTitleWithHTML() {
    let html = "<a href='#'>foo</a>".data(using: .utf8)
    let item = historyItem(html, .html)
    XCTAssertEqual(item.title, "foo")
  }

  func testImage() {
    let image = NSImage(named: "NSBluetoothTemplate")!
    let item = historyItem(image)
    XCTAssertEqual(item.title, "")
  }

  func testFile() {
    let url = URL(fileURLWithPath: "/tmp/foo.bar")
    let item = historyItem(url)
    XCTAssertEqual(item.title, "file:///tmp/foo.bar")
  }

  func testFileWithEscapedChars() {
    let url = URL(fileURLWithPath: "/tmp/产品培训/产品培训.txt")
    let item = historyItem(url)
    XCTAssertEqual(item.title, "file:///tmp/产品培训/产品培训.txt")
  }

  func testTextFromUniversalClipboard() {
    let url = URL(fileURLWithPath: "/tmp/foo.bar")
    let fileURLContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.fileURL.rawValue,
      value: url.dataRepresentation
    )
    let textContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.string.rawValue,
      value: url.lastPathComponent.data(using: .utf8)
    )
    let universalClipboardContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.universalClipboard.rawValue,
      value: "".data(using: .utf8)
    )
    let item = HistoryItem(contents: [fileURLContent, textContent, universalClipboardContent])
    XCTAssertEqual(item.title, "foo.bar")
  }

  func testImageFromUniversalClipboard() {
    let url = Bundle(for: type(of: self)).url(forResource: "guy", withExtension: "jpeg")!
    let fileURLContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.fileURL.rawValue,
      value: url.dataRepresentation
    )
    let universalClipboardContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.universalClipboard.rawValue,
      value: "".data(using: .utf8)
    )
    let item = HistoryItem(contents: [fileURLContent, universalClipboardContent])
    XCTAssertEqual(item.image!.tiffRepresentation, NSImage(data: try! Data(contentsOf: url))!.tiffRepresentation)
  }

  func testFileFromUniversalClipboard() {
    let url = URL(fileURLWithPath: "/tmp/foo.bar")
    let fileURLContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.fileURL.rawValue,
      value: url.dataRepresentation
    )
    let universalClipboardContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.universalClipboard.rawValue,
      value: "".data(using: .utf8)
    )
    let item = HistoryItem(contents: [fileURLContent, universalClipboardContent])
    XCTAssertEqual(item.title, "file:///tmp/foo.bar")
  }

  func testItemWithoutData() {
    let item = historyItem(nil)
    XCTAssertEqual(item.title, "")
  }

  func testPinHasToBeUnique() {
    let item1 = historyItem("foo")
    item1.pin = "a"
    let item2 = historyItem("bar")
    item2.pin = "a"
    XCTAssertThrowsError(try CoreDataManager.shared.viewContext.save())
  }

  func testPinHasToBeLetter() {
    let item1 = historyItem("foo")
    item1.pin = "1"
    XCTAssertThrowsError(try CoreDataManager.shared.viewContext.save())
  }

  func testPinHasToBeLowercased() {
    let item1 = historyItem("foo")
    item1.pin = "C"
    XCTAssertThrowsError(try CoreDataManager.shared.viewContext.save())
  }

  func testPinCanBeEmpty() {
    let item1 = historyItem("foo")
    item1.pin = ""
    XCTAssertNoThrow(try CoreDataManager.shared.viewContext.save())
    XCTAssertEqual(item1.pin, "")
  }

  func testSeveralItemsCanHaveEmptyPin() {
    let item1 = historyItem("foo")
    item1.pin = ""
    let item2 = historyItem("bar")
    item2.pin = ""
    XCTAssertNoThrow(try CoreDataManager.shared.viewContext.save())
    XCTAssertEqual(item1.pin, "")
    XCTAssertEqual(item2.pin, "")
  }

  private func historyItem(_ value: String?) -> HistoryItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                     value: value?.data(using: .utf8))
    return HistoryItem(contents: [content])
  }

  private func historyItem(_ data: Data?, _ type: NSPasteboard.PasteboardType) -> HistoryItem {
    let content = HistoryItemContent(type: type.rawValue,
                                     value: data)
    return HistoryItem(contents: [content])
  }

  private func historyItem(_ value: NSImage) -> HistoryItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue,
                                     value: value.tiffRepresentation!)
    return HistoryItem(contents: [content])
  }

  private func historyItem(_ value: URL) -> HistoryItem {
    let fileURLContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.fileURL.rawValue,
      value: value.dataRepresentation
    )
    let fileNameContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.string.rawValue,
      value: value.lastPathComponent.data(using: .utf8)
    )
    return HistoryItem(contents: [fileURLContent, fileNameContent])
  }
}
// swiftlint:enable force_try
