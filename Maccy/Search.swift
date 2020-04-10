import AppKit
import Fuse

class Search {
  typealias Searchable = [HistoryMenuItem]

  private let fuse = Fuse(threshold: 0.7) // threshold found by trial-and-error

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
    let searchResults = within.map({ historyItem in
      let itemString = historyItem.value
      return (score: self.fuse.search(string, in: itemString)?.score, object: historyItem)
    } as (HistoryMenuItem) -> (score: Double?, object: HistoryMenuItem))
    let matchedResults = searchResults.filter({ $0.score != nil })
    let sortedResults = matchedResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
    return sortedResults.map({ $0.object })
  }

  private func simpleSearch(string: String, within: Searchable) -> Searchable {
    return within.filter({ item in
      let value = item.value
      let range = value.range(
        of: string,
        options: .caseInsensitive,
        range: nil,
        locale: nil
      )

      return (range != nil)
    })
  }
}
