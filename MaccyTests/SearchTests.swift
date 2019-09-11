import XCTest
@testable import Maccy

class SearchTests: XCTestCase {
  let savedFuzzySearch = UserDefaults.standard.bool(forKey: "fuzzySearch")

  let items = [
    NSMenuItem(title: "foo bar baz", action: nil, keyEquivalent: ""),
    NSMenuItem(title: "foo bar zaz", action: nil, keyEquivalent: ""),
    NSMenuItem(title: "xxx yyy zzz", action: nil, keyEquivalent: "")
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

  private func search(_ string: String) -> [NSMenuItem] {
    return Search().search(string: string, within: items)
  }
}
