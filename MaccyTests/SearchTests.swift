import AppKit
import Testing
import Defaults
@testable import Maccy

extension SharedStateTests {
  @MainActor
  final class SearchTests {
    let savedSearchMode = Defaults[.searchMode]
    let items: [Search.Searchable]

    init() {
      items = [
        HistoryItemDecorator(Self.historyItemWithTitle("foo bar baz")),
        HistoryItemDecorator(Self.historyItemWithTitle("foo bar zaz")),
        HistoryItemDecorator(Self.historyItemWithTitle("xxx yyy zzz"))
      ]
    }

    deinit {
      Defaults[.searchMode] = savedSearchMode
    }

    @Test("Simple search")
    func simpleSearch() { // swiftlint:disable:this function_body_length
      Defaults[.searchMode] = Search.Mode.exact
      #expect(search("") == [
        Search.SearchResult(score: nil, object: items[0], ranges: []),
        Search.SearchResult(score: nil, object: items[1], ranges: []),
        Search.SearchResult(score: nil, object: items[2], ranges: [])
      ])
      #expect(search("z") == [
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
      #expect(search("foo") == [
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
      #expect(search("za") == [
        Search.SearchResult(
          score: nil,
          object: items[1],
          ranges: [range(from: 8, to: 9, in: items[1])]
        )
      ])
      #expect(search("yyy") == [
        Search.SearchResult(
          score: nil,
          object: items[2],
          ranges: [range(from: 4, to: 6, in: items[2])]
        )
      ])
      #expect(search("fbb") == [])
      #expect(search("m") == [])
    }

    @Test("Fuzzy search")
    func fuzzySearch() { // swiftlint:disable:this function_body_length
      Defaults[.searchMode] = Search.Mode.fuzzy
      #expect(search("") == [
        Search.SearchResult(score: nil, object: items[0], ranges: []),
        Search.SearchResult(score: nil, object: items[1], ranges: []),
        Search.SearchResult(score: nil, object: items[2], ranges: [])
      ])
      #expect(search("z") == [
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
      #expect(search("foo") == [
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
      #expect(search("za") == [
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
      #expect(search("yyy") == [
        Search.SearchResult(
          score: 0.04,
          object: items[2],
          ranges: [range(from: 4, to: 6, in: items[2])]
        )
      ])
      #expect(search("fbb") == [
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
      #expect(search("m") == [])
    }

    @Test("Regexp search")
    func regexpSearch() { // swiftlint:disable:this function_body_length
      Defaults[.searchMode] = Search.Mode.regexp
      #expect(search("") == [
        Search.SearchResult(score: nil, object: items[0], ranges: []),
        Search.SearchResult(score: nil, object: items[1], ranges: []),
        Search.SearchResult(score: nil, object: items[2], ranges: [])
      ])
      #expect(search("z+") == [
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
      #expect(search("z*") == [
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
      #expect(search("^foo") == [
        Search.SearchResult(
          score: nil,
          object: items[0], ranges: [range(from: 0, to: 2, in: items[0])]
        ),
        Search.SearchResult(
          score: nil,
          object: items[1], ranges: [range(from: 0, to: 2, in: items[1])]
        )
      ])
      #expect(search(" za") == [
        Search.SearchResult(
          score: nil,
          object: items[1],
          ranges: [range(from: 7, to: 9, in: items[1])]
        )
      ])
      #expect(search("[y]+") == [
        Search.SearchResult(
          score: nil,
          object: items[2],
          ranges: [range(from: 4, to: 6, in: items[2])]
        )
      ])
      #expect(search("fbb") == [])
      #expect(search("m") == [])
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

    private static func historyItemWithTitle(_ value: String?) -> HistoryItem {
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
  }
}
