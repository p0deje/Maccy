import XCTest
import Defaults
@testable import Maccy

// swiftlint:disable force_try
/// Tests for `HistoryItem` title generation, content accessors, and the
/// universal-clipboard read paths.
@MainActor
class HistoryItemTests: XCTestCase {
  /// A plain-string content entry yields its text as the title.
  func testTitleForString() {
    let title = "foo"
    let item = historyItem(title)
    XCTAssertEqual(item.title, title)
  }

  /// Leading/trailing whitespace in a title is rendered with middle-dot markers.
  func testTitleWithWhitespaces() {
    let title = "   foo bar   "
    let item = historyItem(title)
    XCTAssertEqual(item.title, "···foo bar···")
  }

  /// Newlines in a title are rendered with the return symbol.
  func testTitleWithNewlines() {
    let title = "\nfoo\nbar\n"
    let item = historyItem(title)
    XCTAssertEqual(item.title, "⏎foo⏎bar⏎")
  }

  /// Tabs in a title are rendered with the tab symbol.
  func testTitleWithTabs() {
    let title = "\tfoo\tbar\t"
    let item = historyItem(title)
    XCTAssertEqual(item.title, "⇥foo⇥bar⇥")
  }

  /// An RTF content entry yields its plain-text content as the title.
  func testTitleWithRTF() {
    let rtf = NSAttributedString(string: "foo").rtf(
      from: NSRange(0...2),
      documentAttributes: [:]
    )
    let item = historyItem(rtf, .rtf)
    XCTAssertEqual(item.title, "foo")
  }

  /// An HTML content entry yields its plain-text content as the title.
  func testTitleWithHTML() {
    let html = "<a href='#'>foo</a>".data(using: .utf8)
    let item = historyItem(html, .html)
    XCTAssertEqual(item.title, "foo")
  }

  /// An image content entry yields an empty title.
  func testImage() {
    let image = NSImage(named: "NSBluetoothTemplate")!
    let item = historyItem(image)
    XCTAssertEqual(item.title, "")
  }

  /// A file-URL content entry yields the URL string as the title.
  func testFile() {
    let url = URL(fileURLWithPath: "/tmp/foo.bar")
    let item = historyItem(url)
    XCTAssertEqual(item.title, "file:///tmp/foo.bar")
  }

  /// A file URL with non-ASCII path segments keeps its escaped form in the title.
  func testFileWithEscapedChars() {
    let url = URL(fileURLWithPath: "/tmp/产品培训/产品培训.txt")
    let item = historyItem(url)
    XCTAssertEqual(item.title, "file:///tmp/产品培训/产品培训.txt")
  }

  /// A file URL from universal clipboard yields its filename as the title.
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
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [fileURLContent, textContent, universalClipboardContent]
    item.title = item.generateTitle()
    XCTAssertEqual(item.title, "foo.bar")
  }

  /// An image file URL from universal clipboard decodes to its image data.
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
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [fileURLContent, universalClipboardContent]
    XCTAssertEqual(item.image!.tiffRepresentation, NSImage(data: try! Data(contentsOf: url))!.tiffRepresentation)
  }

  /// An oversized image from universal clipboard is ignored (no image data loaded).
  func testOversizedImageFromUniversalClipboardIsIgnored() {
    let savedMaxClipboardContentSize = Defaults[.maxClipboardContentSize]
    Defaults[.maxClipboardContentSize] = 1
    defer {
      Defaults[.maxClipboardContentSize] = savedMaxClipboardContentSize
    }

    let url = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString).jpeg")
    try? Data(count: HistoryItemContent.maxValueSize + 1).write(to: url)
    defer {
      try? FileManager.default.removeItem(at: url)
    }

    let fileURLContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.fileURL.rawValue,
      value: url.dataRepresentation
    )
    let universalClipboardContent = HistoryItemContent(
      type: NSPasteboard.PasteboardType.universalClipboard.rawValue,
      value: "".data(using: .utf8)
    )
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [fileURLContent, universalClipboardContent]
    XCTAssertNil(item.imageData)
  }

  /// A file URL from universal clipboard yields its URL string as the title.
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
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [fileURLContent, universalClipboardContent]
    item.title = item.generateTitle()
    XCTAssertEqual(item.title, "file:///tmp/foo.bar")
  }

  /// A content entry with no data yields an empty title.
  func testItemWithoutData() {
    let item = historyItem(nil)
    XCTAssertEqual(item.title, "")
  }

  /// The title is truncated to `titlePreviewLimit` for very long text.
  func testLargeTextTitleIsBounded() {
    let item = historyItem(String(repeating: "a", count: 50_000))
    XCTAssertEqual(item.title.count, HistoryItem.titlePreviewLimit)
  }

  /// Benchmark for `generateTitle` over large text, amplified to overcome timer jitter.
  func testLargeTextTitleBenchmark() {
    let item = historyItem(String(repeating: "abcdef\n", count: 20_000))

    // generateTitle is ~170µs, noise-dominated per-call on the shared runner
    // (chronic RSD ~20–40% vs the 10% gate). Amplify N× per sample so the
    // signal rises above timer jitter.
    _ = item.generateTitle()
    measure {
      for _ in 0..<100 {
        _ = item.generateTitle()
      }
    }
  }

  /// `textPrefix(maxLength:)` never splits a multibyte character.
  func testTextPrefixDoesNotSplitMultibyteCharacters() {
    let item = historyItem("😀😀")
    XCTAssertEqual(item.textPrefix(maxLength: 5), "😀")
  }

  /// `imageData` selects the image content entry by configured type priority.
  func testContentDataUsesRequestedTypePriority() {
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [
      HistoryItemContent(type: NSPasteboard.PasteboardType.png.rawValue, value: "png".data(using: .utf8)),
      HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: "tiff".data(using: .utf8))
    ]

    XCTAssertEqual(item.imageData, "tiff".data(using: .utf8))
  }

  /// `supersedes` matches content entries by type even when they carry no data.
  func testSupersedesHandlesContentWithoutData() {
    let type = "org.maccy.EmptyTestType"
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = [HistoryItemContent(type: type)]

    let other = HistoryItem()
    Storage.shared.context.insert(other)
    other.contents = [HistoryItemContent(type: type)]

    let different = HistoryItem()
    Storage.shared.context.insert(different)
    different.contents = [HistoryItemContent(type: "\(type).Other")]

    XCTAssertTrue(item.supersedes(other))
    XCTAssertFalse(item.supersedes(different))
  }

  /// `shortened(to:)` truncates a string to the given length.
  func testStringShortenedDoesNotExceedMaxLength() {
    XCTAssertEqual("abcd".shortened(to: 3), "abc")
  }

  /// `nearest(to:where:)` searches the whole collection, not just one side of the index.
  func testNearestUsesSliceAbsoluteIndexes() {
    XCTAssertEqual([1, 2, 3, 4].nearest(to: 2, where: { $0 == 4 }), 4)
    XCTAssertEqual([1, 2, 3, 4].nearest(to: 3, where: { $0 == 1 }), 1)
  }

  /// `removeValues(where:)` filters by value without mutating during iteration.
  func testDictionaryRemoveValuesDoesNotMutateDuringIteration() {
    var dictionary = ["a": 1, "b": 2, "c": 3]
    dictionary.removeValues { $0.isMultiple(of: 2) }
    XCTAssertEqual(dictionary, ["a": 1, "c": 3])
  }

  /// Multiple items can persist with an empty-string pin simultaneously.
  func testSeveralItemsCanHaveEmptyPin() {
    let item1 = historyItem("foo")
    item1.pin = ""
    let item2 = historyItem("bar")
    item2.pin = ""
    XCTAssertNoThrow(try Storage.shared.context.save())
    XCTAssertEqual(item1.pin, "")
    XCTAssertEqual(item2.pin, "")
  }

  /// Builds and inserts an item backed by a single UTF-8 string content entry.
  private func historyItem(_ value: String?) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value?.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()

    return item
  }

  /// Builds and inserts an item backed by a single raw-data content entry of the given type.
  private func historyItem(_ data: Data?, _ type: NSPasteboard.PasteboardType) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: type.rawValue,
        value: data
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()

    return item
  }

  /// Builds and inserts an item backed by a TIFF image content entry.
  private func historyItem(_ value: NSImage) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.tiff.rawValue,
        value: value.tiffRepresentation!
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()

    return item
  }

  /// Builds and inserts an item backed by a file-URL content entry (URL plus filename string).
  private func historyItem(_ value: URL) -> HistoryItem {
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fileURL.rawValue,
        value: value.dataRepresentation
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: value.lastPathComponent.data(using: .utf8)
      )
    ]
    let item = HistoryItem()
    Storage.shared.context.insert(item)
    item.contents = contents
    item.title = item.generateTitle()

    return item
  }
}
// swiftlint:enable force_try
