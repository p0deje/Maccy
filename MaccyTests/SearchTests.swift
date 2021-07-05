import XCTest
@testable import Maccy

class SearchTests: XCTestCase {
  let savedFuzzySearch = UserDefaults.standard.fuzzySearch
  var items: [Search.Searchable]!

  override func setUp() {
    CoreDataManager.inMemory = true
    super.setUp()
  }

  override func tearDown() {
    super.tearDown()
    CoreDataManager.inMemory = false
    UserDefaults.standard.fuzzySearch = savedFuzzySearch
  }

  func testSimpleSearchInTitle() {
    UserDefaults.standard.fuzzySearch = false
    items = [
      Menu.IndexedItem(value: "foo bar baz", item: historyItemWithTitle("foo bar baz"), menuItems: []),
      Menu.IndexedItem(value: "foo bar zaz", item: historyItemWithTitle("foo bar zaz"), menuItems: []),
      Menu.IndexedItem(value: "xxx yyy zzz", item: historyItemWithTitle("xxx yyy zzz"), menuItems: [])
    ]

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], titleMatches: []),
      Search.SearchResult(score: nil, object: items[1], titleMatches: []),
      Search.SearchResult(score: nil, object: items[2], titleMatches: [])
    ])
    XCTAssertEqual(search("z"), [
      Search.SearchResult(score: nil, object: items[0], titleMatches: [10...10]),
      Search.SearchResult(score: nil, object: items[1], titleMatches: [8...8]),
      Search.SearchResult(score: nil, object: items[2], titleMatches: [8...8])
    ])
    XCTAssertEqual(search("foo"), [
      Search.SearchResult(score: nil, object: items[0], titleMatches: [0...2]),
      Search.SearchResult(score: nil, object: items[1], titleMatches: [0...2])
    ])
    XCTAssertEqual(search("za"), [
      Search.SearchResult(score: nil, object: items[1], titleMatches: [8...9])
    ])
    XCTAssertEqual(search("yyy"), [
      Search.SearchResult(score: nil, object: items[2], titleMatches: [4...6])
    ])
    XCTAssertEqual(search("fbb"), [])
    XCTAssertEqual(search("m"), [])
  }

  func testSimpleSearchInContents() {
    UserDefaults.standard.fuzzySearch = false
    items = [
      Menu.IndexedItem(value: "foo bar baz", item: historyItemWithoutTitle("foo bar baz"), menuItems: []),
      Menu.IndexedItem(value: "foo bar zaz", item: historyItemWithoutTitle("foo bar zaz"), menuItems: []),
      Menu.IndexedItem(value: "xxx yyy zzz", item: historyItemWithoutTitle("xxx yyy zzz"), menuItems: [])
    ]

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], titleMatches: []),
      Search.SearchResult(score: nil, object: items[1], titleMatches: []),
      Search.SearchResult(score: nil, object: items[2], titleMatches: [])
    ])
    XCTAssertEqual(search("z"), [
      Search.SearchResult(score: nil, object: items[0], titleMatches: []),
      Search.SearchResult(score: nil, object: items[1], titleMatches: []),
      Search.SearchResult(score: nil, object: items[2], titleMatches: [])
    ])
    XCTAssertEqual(search("foo"), [
      Search.SearchResult(score: nil, object: items[0], titleMatches: []),
      Search.SearchResult(score: nil, object: items[1], titleMatches: [])
    ])
    XCTAssertEqual(search("za"), [
      Search.SearchResult(score: nil, object: items[1], titleMatches: [])
    ])
    XCTAssertEqual(search("yyy"), [
      Search.SearchResult(score: nil, object: items[2], titleMatches: [])
    ])
    XCTAssertEqual(search("fbb"), [])
    XCTAssertEqual(search("m"), [])
  }

  func testFuzzySearchInTitle() {
    UserDefaults.standard.fuzzySearch = true
    items = [
      Menu.IndexedItem(value: "foo bar baz", item: historyItemWithTitle("foo bar baz"), menuItems: []),
      Menu.IndexedItem(value: "foo bar zaz", item: historyItemWithTitle("foo bar zaz"), menuItems: []),
      Menu.IndexedItem(value: "xxx yyy zzz", item: historyItemWithTitle("xxx yyy zzz"), menuItems: [])
    ]

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], titleMatches: []),
      Search.SearchResult(score: nil, object: items[1], titleMatches: []),
      Search.SearchResult(score: nil, object: items[2], titleMatches: [])
    ])
    XCTAssertEqual(search("z"), [
      Search.SearchResult(score: 0.08, object: items[1], titleMatches: [8...8, 10...10]),
      Search.SearchResult(score: 0.08, object: items[2], titleMatches: [8...10]),
      Search.SearchResult(score: 0.1, object: items[0], titleMatches: [10...10])
    ])
    XCTAssertEqual(search("foo"), [
      Search.SearchResult(score: 0.0, object: items[0], titleMatches: [0...2]),
      Search.SearchResult(score: 0.0, object: items[1], titleMatches: [0...2])
    ])
    XCTAssertEqual(search("za"), [
      Search.SearchResult(score: 0.08, object: items[1], titleMatches: [5...5, 8...9]),
      Search.SearchResult(score: 0.54, object: items[0], titleMatches: [5...5, 9...10]),
      Search.SearchResult(score: 0.58, object: items[2], titleMatches: [8...10])
    ])
    XCTAssertEqual(search("yyy"), [
      Search.SearchResult(score: 0.04, object: items[2], titleMatches: [4...6])
    ])
    XCTAssertEqual(search("fbb"), [
      Search.SearchResult(score: 0.6666666666666666, object: items[0], titleMatches: [0...0, 4...4, 8...8]),
      Search.SearchResult(score: 0.6666666666666666, object: items[1], titleMatches: [0...0, 4...4])
    ])
    XCTAssertEqual(search("m"), [])
  }

  func testFuzzySearchInContents() {
    UserDefaults.standard.fuzzySearch = true
    items = [
      Menu.IndexedItem(value: "foo bar baz", item: historyItemWithoutTitle("foo bar baz"), menuItems: []),
      Menu.IndexedItem(value: "foo bar zaz", item: historyItemWithoutTitle("foo bar zaz"), menuItems: []),
      Menu.IndexedItem(value: "xxx yyy zzz", item: historyItemWithoutTitle("xxx yyy zzz"), menuItems: [])
    ]

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], titleMatches: []),
      Search.SearchResult(score: nil, object: items[1], titleMatches: []),
      Search.SearchResult(score: nil, object: items[2], titleMatches: [])
    ])
    XCTAssertEqual(search("z"), [
      Search.SearchResult(score: 0.08, object: items[1], titleMatches: []),
      Search.SearchResult(score: 0.08, object: items[2], titleMatches: []),
      Search.SearchResult(score: 0.1, object: items[0], titleMatches: [])
    ])
    XCTAssertEqual(search("foo"), [
      Search.SearchResult(score: 0.0, object: items[0], titleMatches: []),
      Search.SearchResult(score: 0.0, object: items[1], titleMatches: [])
    ])
    XCTAssertEqual(search("za"), [
      Search.SearchResult(score: 0.08, object: items[1], titleMatches: []),
      Search.SearchResult(score: 0.54, object: items[0], titleMatches: []),
      Search.SearchResult(score: 0.58, object: items[2], titleMatches: [])
    ])
    XCTAssertEqual(search("yyy"), [
      Search.SearchResult(score: 0.04, object: items[2], titleMatches: [])
    ])
    XCTAssertEqual(search("fbb"), [
      Search.SearchResult(score: 0.6666666666666666, object: items[0], titleMatches: []),
      Search.SearchResult(score: 0.6666666666666666, object: items[1], titleMatches: [])
    ])
    XCTAssertEqual(search("m"), [])
  }

  private func search(_ string: String) -> [Search.SearchResult] {
    return Search().search(string: string, within: items)
  }

  private func historyItemWithTitle(_ value: String?) -> HistoryItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                     value: value?.data(using: .utf8))
    return HistoryItem(contents: [content])
  }

  private func historyItemWithoutTitle(_ value: String?) -> HistoryItem {
    let content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                     value: value?.data(using: .utf8))
    let item = HistoryItem(contents: [content])
    item.title = ""
    return item
  }
}
