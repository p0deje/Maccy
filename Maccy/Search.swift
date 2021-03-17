import AppKit
import Fuse

class Search {
  struct FuzzySearchResult {
    var score: Double?
    var object: Menu.IndexedItem
  }

  typealias Searchable = [Menu.IndexedItem]

  private let fuse = Fuse(threshold: 0.7) // threshold found by trial-and-error
  private let fuzzySearchLimit = 5_000

  func search(string: String, within: Searchable) -> Searchable {
    guard !string.isEmpty else {
      return within
    }

    if UserDefaults.standard.fuzzySearch {
      return fuzzySearch(string: string, within: within)
    } else {
      return simpleSearch(string: string, within: within)
    }
  }

  private func fuzzySearch(string: String, within: Searchable) -> Searchable {
    let pattern = fuse.createPattern(from: string)
    let searchResults: [FuzzySearchResult] = within.compactMap({ item in
      var searchString = item.value
      if searchString.count > fuzzySearchLimit {
        // shortcut to avoid slow search
        let stopIndex = searchString.index(searchString.startIndex, offsetBy: fuzzySearchLimit)
        searchString = "\(searchString[...stopIndex])"
      }

      if let fuzzyScore = fuse.search(pattern, in: searchString)?.score {
        return FuzzySearchResult(score: fuzzyScore, object: item)
      } else {
        return nil
      }
    })
    let sortedResults = searchResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
    return sortedResults.map({ $0.object })
  }

  private func simpleSearch(string: String, within: Searchable) -> Searchable {
    return within.filter({ item in
      let range = item.value.range(
        of: string,
        options: .caseInsensitive,
        range: nil,
        locale: nil
      )

      return (range != nil)
    })
  }
}
