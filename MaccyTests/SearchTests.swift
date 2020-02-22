import XCTest
@testable import Maccy

class SearchTests: XCTestCase {
  let savedFuzzySearch = UserDefaults.standard.bool(forKey: "fuzzySearch")

  let items: Search.Searchable = [
    HistoryMenuItem(item: HistoryItem(value: "foo bar baz"), onSelected: { _ in }),
    HistoryMenuItem(item: HistoryItem(value: "foo bar zaz"), onSelected: { _ in }),
    HistoryMenuItem(item: HistoryItem(value: "xxx yyy zzz"), onSelected: { _ in })
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

  private func search(_ string: String) -> Search.Searchable {
    return Search().search(string: string, within: items)
  }
}
