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

    @Test("Search by kind")
    func searchByKind() {
      Defaults[.searchMode] = Search.Mode.exact
      let text = HistoryItemDecorator(Self.historyItemWithTitle("foo bar"))
      let image = HistoryItemDecorator(Self.historyItemWithImage(NSImage(named: "NSInfo")!))
      let file = HistoryItemDecorator(Self.historyItemWithFileURL(URL(fileURLWithPath: "/tmp/foo.bar")))
      let items = [text, image, file]

      #expect(objects(search("", within: items)) == [text, image, file])
      #expect(objects(search("type:text", within: items)) == [text])
      #expect(objects(search("type:image", within: items)) == [image])
      #expect(objects(search("type:file", within: items)) == [file])
      #expect(objects(search("type:IMAGE", within: items)) == [image])
      #expect(objects(search("type:image type:file", within: items)) == [image, file])

      // The rest of the query keeps going through the search mode.
      #expect(objects(search("type:file foo", within: items)) == [file])
      #expect(objects(search("foo type:text", within: items)) == [text])
      #expect(objects(search("type:file zzz", within: items)) == [])

      // A word naming an unknown kind is searched for as it is.
      #expect(objects(search("type:folder", within: items)) == [])
      #expect(objects(search("type:", within: items)) == [])
    }

    private func search(_ string: String) -> [Search.SearchResult] {
      return search(string, within: items)
    }

    private func search(_ string: String, within items: [Search.Searchable]) -> [Search.SearchResult] {
      return Search().search(string: string, within: items)
    }

    private func objects(_ results: [Search.SearchResult]) -> [Search.Searchable] {
      return results.map(\.object)
    }

    // swiftlint:disable:next identifier_name
    private func range(from: Int, to: Int, in item: HistoryItemDecorator) -> Range<String.Index> {
      let startIndex = item.title.startIndex
      let lowerBound = item.title.index(startIndex, offsetBy: from)
      let upperBound = item.title.index(startIndex, offsetBy: to + 1)

      return lowerBound..<upperBound
    }

    private static func historyItemWithTitle(_ value: String?) -> HistoryItem {
      return historyItem([
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: value?.data(using: .utf8)
        )
      ])
    }

    private static func historyItemWithImage(_ value: NSImage) -> HistoryItem {
      return historyItem([
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.tiff.rawValue,
          value: value.tiffRepresentation!
        )
      ])
    }

    private static func historyItemWithFileURL(_ value: URL) -> HistoryItem {
      return historyItem([
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.fileURL.rawValue,
          value: value.dataRepresentation
        ),
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: value.lastPathComponent.data(using: .utf8)
        )
      ])
    }

    private static func historyItem(_ contents: [HistoryItemContent]) -> HistoryItem {
      let item = HistoryItem()
      Storage.shared.context.insert(item)
      item.contents = contents
      item.title = item.generateTitle()

      return item
    }
  }
}
