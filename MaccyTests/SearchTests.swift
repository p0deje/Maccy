import XCTest
import Defaults
@testable import Maccy

class SearchTests: XCTestCase {
  let savedSearchMode = Defaults[.searchMode]
  var items: [Search.Searchable]!

  override func tearDown() {
    super.tearDown()
    Defaults[.searchMode] = savedSearchMode
  }

  func testParsedQuery() {
    // "#kod docker" -> tag: "kod", text: "docker"
    let q1 = Search.ParsedQuery(from: "#kod docker")
    XCTAssertEqual(q1.tag, "kod")
    XCTAssertEqual(q1.text, "docker")

    // "#" (alone) -> tag: "", text: ""
    let q2 = Search.ParsedQuery(from: "#")
    XCTAssertEqual(q2.tag, "")
    XCTAssertEqual(q2.text, "")

    // "docker" -> tag: nil, text: "docker"
    let q3 = Search.ParsedQuery(from: "docker")
    XCTAssertNil(q3.tag)
    XCTAssertEqual(q3.text, "docker")

    // Case sensitivity is handled in the init part with dropFirst().
    // It was used with lowercased() in the search part.
    // The parsed string should be directly "#İŞ" -> "İŞ".
    let q4 = Search.ParsedQuery(from: "#İŞ")
    XCTAssertEqual(q4.tag, "İŞ")
    XCTAssertEqual(q4.text, "")
  }

  @MainActor
  func testSimpleSearch() { // swiftlint:disable:this function_body_length
    Defaults[.searchMode] = Search.Mode.exact
    items = [
      HistoryItemDecorator(historyItemWithTitle("foo bar baz")),
      HistoryItemDecorator(historyItemWithTitle("foo bar zaz")),
      HistoryItemDecorator(historyItemWithTitle("xxx yyy zzz"))
    ]

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], ranges: []),
      Search.SearchResult(score: nil, object: items[1], ranges: []),
      Search.SearchResult(score: nil, object: items[2], ranges: [])
    ])
    XCTAssertEqual(search("z"), [
      Search.SearchResult(
        score: nil,
        object: items[0],
        ranges: [range(from: 10, to: 10, in: items[0])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 8, to: 8, in: items[1])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[2],
        ranges: [range(from: 8, to: 8, in: items[2])]
      )
    ])
    XCTAssertEqual(search("foo"), [
      Search.SearchResult(
        score: nil,
        object: items[0],
        ranges: [range(from: 0, to: 2, in: items[0])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 0, to: 2, in: items[1])]
      )
    ])
    XCTAssertEqual(search("za"), [
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 8, to: 9, in: items[1])]
      )
    ])
    XCTAssertEqual(search("yyy"), [
      Search.SearchResult(
        score: nil,
        object: items[2],
        ranges: [range(from: 4, to: 6, in: items[2])]
      )
    ])
    XCTAssertEqual(search("fbb"), [])
    XCTAssertEqual(search("m"), [])
  }

  @MainActor
  func testFuzzySearch() { // swiftlint:disable:this function_body_length
    Defaults[.searchMode] = Search.Mode.fuzzy
    items = [
      HistoryItemDecorator(historyItemWithTitle("foo bar baz")),
      HistoryItemDecorator(historyItemWithTitle("foo bar zaz")),
      HistoryItemDecorator(historyItemWithTitle("xxx yyy zzz"))
    ]

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], ranges: []),
      Search.SearchResult(score: nil, object: items[1], ranges: []),
      Search.SearchResult(score: nil, object: items[2], ranges: [])
    ])
    XCTAssertEqual(search("z"), [
      Search.SearchResult(
        score: 0.08,
        object: items[1],
        ranges: [range(from: 8, to: 8, in: items[1]), range(from: 10, to: 10, in: items[1])]
      ),
      Search.SearchResult(
        score: 0.08,
        object: items[2],
        ranges: [range(from: 8, to: 10, in: items[2])]
      ),
      Search.SearchResult(
        score: 0.1,
        object: items[0],
        ranges: [range(from: 10, to: 10, in: items[0])]
      )
    ])
    XCTAssertEqual(search("foo"), [
      Search.SearchResult(
        score: 0.0,
        object: items[0],
        ranges: [range(from: 0, to: 2, in: items[0])]
      ),
      Search.SearchResult(
        score: 0.0,
        object: items[1],
        ranges: [range(from: 0, to: 2, in: items[1])]
      )
    ])
    XCTAssertEqual(search("za"), [
      Search.SearchResult(
        score: 0.08,
        object: items[1],
        ranges: [range(from: 5, to: 5, in: items[1]), range(from: 8, to: 9, in: items[1])]
      ),
      Search.SearchResult(
        score: 0.54,
        object: items[0],
        ranges: [range(from: 5, to: 5, in: items[0]), range(from: 9, to: 10, in: items[0])]
      ),
      Search.SearchResult(
        score: 0.58,
        object: items[2],
        ranges: [range(from: 8, to: 10, in: items[2])]
      )
    ])
    XCTAssertEqual(search("yyy"), [
      Search.SearchResult(
        score: 0.04,
        object: items[2],
        ranges: [range(from: 4, to: 6, in: items[2])]
      )
    ])
    XCTAssertEqual(search("fbb"), [
      Search.SearchResult(
        score: 0.6666666666666666,
        object: items[0],
        ranges: [
          range(from: 0, to: 0, in: items[0]),
          range(from: 4, to: 4, in: items[0]),
          range(from: 8, to: 8, in: items[0])
        ]
      ),
      Search.SearchResult(
        score: 0.6666666666666666,
        object: items[1],
        ranges: [range(from: 0, to: 0, in: items[1]), range(from: 4, to: 4, in: items[1])])
    ])
    XCTAssertEqual(search("m"), [])
  }

  @MainActor
  func testRegexpSearch() { // swiftlint:disable:this function_body_length
    Defaults[.searchMode] = Search.Mode.regexp
    items = [
      HistoryItemDecorator(historyItemWithTitle("foo bar baz")),
      HistoryItemDecorator(historyItemWithTitle("foo bar zaz")),
      HistoryItemDecorator(historyItemWithTitle("xxx yyy zzz"))
    ]

    XCTAssertEqual(search(""), [
      Search.SearchResult(score: nil, object: items[0], ranges: []),
      Search.SearchResult(score: nil, object: items[1], ranges: []),
      Search.SearchResult(score: nil, object: items[2], ranges: [])
    ])
    XCTAssertEqual(search("z+"), [
      Search.SearchResult(
        score: nil,
        object: items[0],
        ranges: [range(from: 10, to: 10, in: items[0])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 8, to: 8, in: items[1])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[2],
        ranges: [range(from: 8, to: 10, in: items[2])]
      )
    ])
    XCTAssertEqual(search("z*"), [
      Search.SearchResult(
        score: nil,
        object: items[0],
        ranges: [range(from: 0, to: -1, in: items[0])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 0, to: -1, in: items[1])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[2],
        ranges: [range(from: 0, to: -1, in: items[2])]
      )
    ])
    XCTAssertEqual(search("^foo"), [
      Search.SearchResult(
        score: nil,
        object: items[0], ranges: [range(from: 0, to: 2, in: items[0])]
      ),
      Search.SearchResult(
        score: nil,
        object: items[1], ranges: [range(from: 0, to: 2, in: items[1])]
      )
    ])
    XCTAssertEqual(search(" za"), [
      Search.SearchResult(
        score: nil,
        object: items[1],
        ranges: [range(from: 7, to: 9, in: items[1])]
      )
    ])
    XCTAssertEqual(search("[y]+"), [
      Search.SearchResult(
        score: nil,
        object: items[2],
        ranges: [range(from: 4, to: 6, in: items[2])]
      )
    ])
    XCTAssertEqual(search("fbb"), [])
    XCTAssertEqual(search("m"), [])
  }

  @MainActor
  func testTagSearch() {
    Defaults[.searchMode] = Search.Mode.exact
    items = [
      HistoryItemDecorator(historyItemWithTitle("foo bar baz", tags: ["work", "code"])),
      HistoryItemDecorator(historyItemWithTitle("hello world", tags: ["personal"])),
      HistoryItemDecorator(historyItemWithTitle("xxx yyy zzz", tags: []))
    ]

    // "#work" filters to items tagged "work"
    let workResults = search("#work")
    XCTAssertEqual(workResults.count, 1)
    XCTAssertEqual(workResults[0].object.title, "foo bar baz")

    // "#" alone returns all items with any tag
    let hashResults = search("#")
    XCTAssertEqual(hashResults.count, 2)

    // "#work docker" filters by tag "work" then searches text "docker" (no match)
    let noMatch = search("#work docker")
    XCTAssertEqual(noMatch.count, 0)

    // "#work foo" filters by tag "work" then searches text "foo"
    let tagAndText = search("#work foo")
    XCTAssertEqual(tagAndText.count, 1)
    XCTAssertEqual(tagAndText[0].object.title, "foo bar baz")

    // "#nonexistent" returns nothing
    let noTag = search("#nonexistent")
    XCTAssertEqual(noTag.count, 0)

    // Normal search without "#" returns all matches
    let normalSearch = search("yyy")
    XCTAssertEqual(normalSearch.count, 1)
    XCTAssertEqual(normalSearch[0].object.title, "xxx yyy zzz")
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
  private func historyItemWithTitle(_ value: String?, tags: [String] = []) -> HistoryItem {
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
    item.tags = tags

    return item
  }
}
