import XCTest
@testable import Maccy

class SearchTests: XCTestCase {
  let savedFuzzySearch = UserDefaults.standard.fuzzySearch
  var items: Search.Searchable!

  override func setUp() {
    CoreDataManager.inMemory = true
    super.setUp()
    items = [
      Menu.IndexedItem(value: "foo bar baz", item: nil, menuItems: []),
      Menu.IndexedItem(value: "foo bar zaz", item: nil, menuItems: []),
      Menu.IndexedItem(value: "xxx yyy zzz", item: nil, menuItems: [])
    ]
  }

  override func tearDown() {
    super.tearDown()
    CoreDataManager.inMemory = false
    UserDefaults.standard.fuzzySearch = savedFuzzySearch
  }

  func testSimpleSearch() {
    UserDefaults.standard.fuzzySearch = false

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], matches: []),
      Search.SearchResult(score: nil, object: items[1], matches: []),
      Search.SearchResult(score: nil, object: items[2], matches: [])
    ])
    XCTAssertEqual(search("z"), [
      Search.SearchResult(score: nil, object: items[0], matches: [10...10]),
      Search.SearchResult(score: nil, object: items[1], matches: [8...8]),
      Search.SearchResult(score: nil, object: items[2], matches: [8...8])
    ])
    XCTAssertEqual(search("foo"), [
      Search.SearchResult(score: nil, object: items[0], matches: [0...2]),
      Search.SearchResult(score: nil, object: items[1], matches: [0...2])
    ])
    XCTAssertEqual(search("za"), [
      Search.SearchResult(score: nil, object: items[1], matches: [8...9])
    ])
    XCTAssertEqual(search("yyy"), [
      Search.SearchResult(score: nil, object: items[2], matches: [4...6])
    ])
    XCTAssertEqual(search("fbb"), [])
    XCTAssertEqual(search("m"), [])
  }

  func testFuzzySearch() {
    UserDefaults.standard.fuzzySearch = true

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], matches: []),
      Search.SearchResult(score: nil, object: items[1], matches: []),
      Search.SearchResult(score: nil, object: items[2], matches: [])
    ])
    XCTAssertEqual(search("z"), [
      Search.SearchResult(score: 0.08, object: items[1], matches: [8...8, 10...10]),
      Search.SearchResult(score: 0.08, object: items[2], matches: [8...10]),
      Search.SearchResult(score: 0.1, object: items[0], matches: [10...10])
    ])
    XCTAssertEqual(search("foo"), [
      Search.SearchResult(score: 0.0, object: items[0], matches: [0...2]),
      Search.SearchResult(score: 0.0, object: items[1], matches: [0...2])
    ])
    XCTAssertEqual(search("za"), [
      Search.SearchResult(score: 0.08, object: items[1], matches: [5...5, 8...9]),
      Search.SearchResult(score: 0.54, object: items[0], matches: [5...5, 9...10]),
      Search.SearchResult(score: 0.58, object: items[2], matches: [8...10])
    ])
    XCTAssertEqual(search("yyy"), [
      Search.SearchResult(score: 0.04, object: items[2], matches: [4...6])
    ])
    XCTAssertEqual(search("fbb"), [
      Search.SearchResult(score: 0.6666666666666666, object: items[0], matches: [0...0, 4...4, 8...8]),
      Search.SearchResult(score: 0.6666666666666666, object: items[1], matches: [0...0, 4...4])
    ])
    XCTAssertEqual(search("m"), [])
  }

  private func search(_ string: String) -> [Search.SearchResult] {
    return Search().search(string: string, within: items)
  }
}
