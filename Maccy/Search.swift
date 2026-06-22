import AppKit
import Defaults
import Fuse

class Search {
  enum Mode: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
    case exact
    case fuzzy
    case regexp
    case mixed

    var id: Self { self }

    var description: String {
      switch self {
      case .exact:
        return NSLocalizedString("Exact", tableName: "GeneralSettings", comment: "")
      case .fuzzy:
        return NSLocalizedString("Fuzzy", tableName: "GeneralSettings", comment: "")
      case .regexp:
        return NSLocalizedString("Regex", tableName: "GeneralSettings", comment: "")
      case .mixed:
        return NSLocalizedString("Mixed", tableName: "GeneralSettings", comment: "")
      }
    }
  }

  struct SearchResult: Equatable {
    var score: Double?
    var object: Searchable
    var ranges: [Range<String.Index>] = []
  }

  typealias Searchable = HistoryItemDecorator

  enum ContentTag: String, CaseIterable {
    case image
    case file
    case text

    func matches(_ item: Searchable) -> Bool {
      let hasImage = item.item.imageData != nil
      let hasFile = !item.item.fileURLs.isEmpty

      switch self {
      case .image:
        return hasImage
      case .file:
        return !hasImage && hasFile
      case .text:
        return !hasImage && !hasFile
      }
    }
  }

  struct Query {
    let contentTag: ContentTag?
    let searchString: String

    var includesSnippetResults: Bool {
      contentTag == nil || contentTag == .text
    }

    init(_ string: String) {
      let query = string.drop { $0.isWhitespace }
      let lowercasedQuery = String(query).lowercased()

      for tag in ContentTag.allCases {
        let prefix = "\(tag.rawValue):"
        if lowercasedQuery.hasPrefix(prefix) {
          let contentStart = query.index(query.startIndex, offsetBy: prefix.count)
          // 只在开头识别类型标签，剩余文本继续交给原搜索模式处理。
          self.contentTag = tag
          self.searchString = query[contentStart...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
          return
        }
      }

      self.contentTag = nil
      self.searchString = string
    }
  }

  private let fuse = Fuse(threshold: 0.7) // threshold found by trial-and-error
  private let fuzzySearchLimit = 5_000

  func search(string: String, within: [Searchable]) -> [SearchResult] {
    let query = Query(string)
    let items = query.contentTag.map { tag in
      within.filter { tag.matches($0) }
    } ?? within

    guard !query.searchString.isEmpty else {
      return items.map { SearchResult(object: $0) }
    }

    switch Defaults[.searchMode] {
    case .mixed:
      return mixedSearch(string: query.searchString, within: items)
    case .regexp:
      return simpleSearch(string: query.searchString, within: items, options: .regularExpression)
    case .fuzzy:
      return fuzzySearch(string: query.searchString, within: items)
    default:
      return simpleSearch(string: query.searchString, within: items, options: .caseInsensitive)
    }
  }

  private func fuzzySearch(string: String, within: [Searchable]) -> [SearchResult] {
    let pattern = fuse.createPattern(from: string)
    let searchResults: [SearchResult] = within.compactMap { item in
      fuzzySearch(for: pattern, in: item.title, of: item)
    }
    let sortedResults = searchResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
    return sortedResults
  }

  private func fuzzySearch(
    for pattern: Fuse.Pattern?,
    in searchString: String,
    of item: Searchable
  ) -> SearchResult? {
    var searchString = searchString
    if searchString.count > fuzzySearchLimit {
      // shortcut to avoid slow search
      let stopIndex = searchString.index(searchString.startIndex, offsetBy: fuzzySearchLimit)
      searchString = "\(searchString[...stopIndex])"
    }

    if let fuzzyResult = fuse.search(pattern, in: searchString) {
      return SearchResult(
        score: fuzzyResult.score,
        object: item,
        ranges: fuzzyResult.ranges.map {
          let startIndex = searchString.startIndex
          let lowerBound = searchString.index(startIndex, offsetBy: $0.lowerBound)
          let upperBound = searchString.index(startIndex, offsetBy: $0.upperBound + 1)

          return lowerBound..<upperBound
        }
      )
    } else {
      return nil
    }
  }

  private func simpleSearch(
    string: String,
    within: [Searchable],
    options: NSString.CompareOptions
  ) -> [SearchResult] {
    return within.compactMap { simpleSearch(for: string, in: $0.title, of: $0, options: options) }
  }

  private func simpleSearch(
    for string: String,
    in searchString: String,
    of item: Searchable,
    options: NSString.CompareOptions
  ) -> SearchResult? {
    if let range = searchString.range(of: string, options: options, range: nil, locale: nil) {
      return SearchResult(object: item, ranges: [range])
    } else {
      return nil
    }
  }

  private func mixedSearch(string: String, within: [Searchable]) -> [SearchResult] {
    var results = simpleSearch(string: string, within: within, options: .caseInsensitive)
    guard results.isEmpty else {
      return results
    }

    results = simpleSearch(string: string, within: within, options: .regularExpression)
    guard results.isEmpty else {
      return results
    }

    results = fuzzySearch(string: string, within: within)
    guard results.isEmpty else {
      return results
    }

    return []
  }
}
