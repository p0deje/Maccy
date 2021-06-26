import AppKit
import Fuse

class Search {
  struct SearchResult: Equatable {
    var score: Double?
    var object: Menu.IndexedItem
    var matches: [ClosedRange<Int>]
  }

  typealias Searchable = [Menu.IndexedItem]

  private let fuse = Fuse(threshold: 0.7) // threshold found by trial-and-error
  private let fuzzySearchLimit = 5_000

  func search(string: String, within: Searchable) -> [SearchResult] {
    guard !string.isEmpty else {
      return within.map({ SearchResult(score: nil, object: $0, matches: [])})
    }

    if UserDefaults.standard.fuzzySearch {
      return fuzzySearch(string: string, within: within)
    } else {
      return simpleSearch(string: string, within: within)
    }
  }

  private func fuzzySearch(string: String, within: Searchable) -> [SearchResult] {
    let pattern = fuse.createPattern(from: string)
    let searchResults: [SearchResult] = within.compactMap({ item in
      var searchString = item.value
      if searchString.count > fuzzySearchLimit {
        // shortcut to avoid slow search
        let stopIndex = searchString.index(searchString.startIndex, offsetBy: fuzzySearchLimit)
        searchString = "\(searchString[...stopIndex])"
      }

      if let fuzzyResult = fuse.search(pattern, in: searchString) {
        return SearchResult(
          score: fuzzyResult.score,
          object: item,
          matches: fuzzyResult.ranges
        )
      } else {
        return nil
      }
    })
    let sortedResults = searchResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })

    return sortedResults
  }

  private func simpleSearch(string: String, within: Searchable) -> [SearchResult] {
    return within.compactMap({ item in
      if let range = item.value.range(
        of: string,
        options: .caseInsensitive,
        range: nil,
        locale: nil
      ) {
        let lowerBound = item.value.distance(from: item.value.startIndex, to: range.lowerBound)
        let upperBound = item.value.distance(from: item.value.startIndex, to: range.upperBound) - 1
        return SearchResult(
          score: nil,
          object: item,
          matches: [lowerBound...upperBound]
        )
      } else {
        return nil
      }
    })
  }
}
