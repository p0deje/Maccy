import AppKit
import Fuse

class Search {
  enum Mode: String, CaseIterable {
    case exact
    case fuzzy
    case regexp
    case mixed
  }

  struct SearchResult: Equatable {
    var score: Double?
    var object: Menu.IndexedItem
    var titleMatches: [ClosedRange<Int>]
  }

  typealias Searchable = Menu.IndexedItem

  private let fuse = Fuse(threshold: 0.7) // threshold found by trial-and-error
  private let fuzzySearchLimit = 5_000

  func search(string: String, within: [Searchable]) -> [SearchResult] {
    guard !string.isEmpty else {
      return within.map({ SearchResult(score: nil, object: $0, titleMatches: [])})
    }

    switch Mode(rawValue: UserDefaults.standard.searchMode) {
    case .mixed:
      return mixedSearch(string: string, within: within)
    case .regexp:
      return simpleSearch(string: string, within: within, options: .regularExpression)
    case .fuzzy:
      return fuzzySearch(string: string, within: within)
    default:
      return simpleSearch(string: string, within: within, options: .caseInsensitive)
    }
  }

  private func fuzzySearch(string: String, within: [Searchable]) -> [SearchResult] {
    let pattern = fuse.createPattern(from: string)
    let searchResults: [SearchResult] = within.compactMap({ item in
      fuzzySearch(for: pattern, in: item.title, of: item) ??
        fuzzySearch(for: pattern, in: item.value, of: item)
    })
    let sortedResults = searchResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
    return sortedResults
  }

  private func fuzzySearch(for pattern: Fuse.Pattern?, in searchString: String, of item: Searchable) -> SearchResult? {
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
        titleMatches: fuse.search(pattern, in: item.title)?.ranges ?? []
      )
    } else {
      return nil
    }
  }

  private func simpleSearch(string: String, within: [Searchable], options: NSString.CompareOptions) -> [SearchResult] {
    return within.compactMap({ item in
      simpleSearch(for: string, in: item.title, of: item, options: options) ??
        simpleSearch(for: string, in: item.value, of: item, options: options)
    })
  }

  private func simpleSearch(
    for string: String,
    in searchString: String,
    of item: Searchable,
    options: NSString.CompareOptions
  ) -> SearchResult? {
    if searchString.range(
      of: string,
      options: options,
      range: nil,
      locale: nil
    ) != nil {
      var result = SearchResult(
        score: nil,
        object: item,
        titleMatches: []
      )

      let title = item.title
      if let titleRange = title.range(of: string, options: options, range: nil, locale: nil) {
        let lowerBound = title.distance(from: title.startIndex, to: titleRange.lowerBound)
        var upperBound = title.distance(from: title.startIndex, to: titleRange.upperBound)
        if upperBound > lowerBound {
          upperBound -= 1
        }
        result.titleMatches.append(lowerBound...upperBound)
      }

      return result
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
