import XCTest
import Defaults
@testable import Maccy

class SearchTagTests: XCTestCase {
  let savedSearchMode = Defaults[.searchMode]
  var items: [Search.Searchable]!

  override func tearDown() {
    super.tearDown()
    Defaults[.searchMode] = savedSearchMode
  }

  @MainActor
  func testTagSearchFiltersByClipboardType() {
    Defaults[.searchMode] = Search.Mode.exact
    items = [
      historyItemDecorator(imageTitle: "Image: screenshot"),
      historyItemDecorator(fileTitle: "File: SKILL.md"),
      HistoryItemDecorator(historyItemWithTitle("Text: release notes"))
    ]

    XCTAssertEqual(search("image:"), [Search.SearchResult(object: items[0])])
    XCTAssertEqual(search("file:"), [Search.SearchResult(object: items[1])])
    XCTAssertEqual(search("text:"), [Search.SearchResult(object: items[2])])
  }

  @MainActor
  func testTagSearchIsCaseInsensitiveAndCombinesWithQuery() {
    Defaults[.searchMode] = Search.Mode.exact
    items = [
      historyItemDecorator(imageTitle: "Image: alpha screenshot"),
      historyItemDecorator(imageTitle: "Image: beta screenshot"),
      HistoryItemDecorator(historyItemWithTitle("Text: beta screenshot"))
    ]

    XCTAssertEqual(search("ImAgE: beta"), [
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 7, to: 10, in: items[1])]
      )
    ])
  }

  private func search(_ string: String) -> [Search.SearchResult] {
    return Search().search(string: string, within: items)
  }

  // swiftlint:disable:next identifier_name
  private func range(from: Int, to: Int, in item: HistoryItemDecorator) -> Range<String.Index> {
    let startIndex = item.title.startIndex
    let lowerBound = item.title.index(startIndex, offsetBy: from)
    let upperBound = item.title.index(startIndex, offsetBy: to + 1)

    return lowerBound..<upperBound
  }

  @MainActor
  private func historyItemWithTitle(_ value: String?) -> HistoryItem {
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

  @MainActor
  private func historyItemDecorator(imageTitle title: String) -> HistoryItemDecorator {
    let image = NSImage(named: "StatusBarMenuImage")!
    let item = HistoryItem(contents: [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.tiff.rawValue,
        value: image.tiffRepresentation
      )
    ])
    Storage.shared.context.insert(item)
    item.title = title

    return HistoryItemDecorator(item)
  }

  @MainActor
  private func historyItemDecorator(fileTitle title: String) -> HistoryItemDecorator {
    let url = URL(fileURLWithPath: "/tmp/\(title)")
    let item = HistoryItem(contents: [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.fileURL.rawValue,
        value: url.dataRepresentation
      ),
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: title.data(using: .utf8)
      )
    ])
    Storage.shared.context.insert(item)
    item.title = title

    return HistoryItemDecorator(item)
  }
}
