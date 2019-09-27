import AppKit
import Fuse

class Search {
  private let fuzzySearchPref = "fuzzySearch"
  private let fuse = Fuse(threshold: 0.7) // threshold found by trial-and-error

  init() {
    UserDefaults.standard.register(defaults: [fuzzySearchPref: false])
  }

  func search(string: String, within: [NSMenuItem]) -> [NSMenuItem] {
    guard !string.isEmpty else {
      return within
    }

    if UserDefaults.standard.bool(forKey: fuzzySearchPref)
      && !ProcessInfo.processInfo.arguments.contains("ui-testing") {
      return fuzzySearch(string: string, within: within)
    } else {
      return simpleSearch(string: string, within: within)
    }
  }

  private func fuzzySearch(string: String, within: [NSMenuItem]) -> [NSMenuItem] {
    let searchResults = within.map({ (score: fuse.search(string, in: $0.title)?.score, object: $0) })
    let matchedResults = searchResults.filter({ $0.score != nil })
    let sortedResults = matchedResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
    return sortedResults.map({ $0.object })
  }

  private func simpleSearch(string: String, within: [NSMenuItem]) -> [NSMenuItem] {
    return within.filter({ item in
      let range = item.title.range(
        of: string,
        options: .caseInsensitive,
        range: nil,
        locale: nil
      )

      return (range != nil)
    })
  }
}
