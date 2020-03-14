import XCTest
@testable import Maccy

class SearchTests: XCTestCase {
  let savedFuzzySearch = UserDefaults.standard.bool(forKey: "fuzzySearch")

  let items: Search.Searchable = [
    historyMenuItem("foo bar baz"),
    historyMenuItem("foo bar zaz"),
    historyMenuItem("xxx yyy zzz")
  ]

  override func tearDown() {
    super.tearDown()
    UserDefaults.standard.set(savedFuzzySearch, forKey: "fuzzySearch")
  }

  func testSimpleSearch() {
    UserDefaults.standard.set(false, forKey: "fuzzySearch")

    XCTAssertEqual(search(""), items)
    XCTAssertEqual(search("z"), items)
    XCTAssertEqual(search("foo"), [items[0], items[1]])
    XCTAssertEqual(search("za"), [items[1]])
    XCTAssertEqual(search("yyy"), [items[2]])
    XCTAssertEqual(search("fbb"), [])
    XCTAssertEqual(search("m"), [])
  }

  func testFuzzySearch() {
    UserDefaults.standard.set(true, forKey: "fuzzySearch")

    XCTAssertEqual(search(""), items)
    XCTAssertEqual(search("z"), [items[1], items[2], items[0]])
    XCTAssertEqual(search("foo"), [items[0], items[1]])
    XCTAssertEqual(search("za"), [items[1], items[0], items[2]])
    XCTAssertEqual(search("yyy"), [items[2]])
    XCTAssertEqual(search("fbb"), [items[0], items[1]])
    XCTAssertEqual(search("m"), [])
  }

  private class func historyMenuItem(_ value: String) -> HistoryMenuItem {
    return HistoryMenuItem(item: HistoryItem(value: value.data(using: .utf8)!), onSelected: { _ in })
  }

  private func search(_ string: String) -> Search.Searchable {
    return Search().search(string: string, within: items)
  }
}
