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

  struct Filters {
    var kinds: Set<HistoryItem.Kind> = []
    var applications: [String] = []

    var isEmpty: Bool { kinds.isEmpty && applications.isEmpty }

    // Kinds and applications are each a union, and both have to match.
    func matches(kind: HistoryItem.Kind, application: String?) -> Bool {
      if !kinds.isEmpty && !kinds.contains(kind) {
        return false
      }

      guard !applications.isEmpty else {
        return true
      }

      guard let application else {
        return false
      }

      // Not localized, so "FIN" still matches "Finder" in the Turkish locale.
      return applications.contains { application.range(of: $0, options: .caseInsensitive) != nil }
    }
  }

  private static let kindPrefix = "type:"
  private static let applicationPrefix = "app:"

  private let fuse = Fuse(threshold: 0.7) // threshold found by trial-and-error
  private let fuzzySearchLimit = 5_000

  func search(string: String, within: [Searchable]) -> [SearchResult] {
    let (filters, string) = Self.splitFilters(from: string)
    let within = filters.isEmpty ? within : filter(within, by: filters)

    guard !string.isEmpty else {
      return within.map { SearchResult(object: $0) }
    }

    switch Defaults[.searchMode] {
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

  // Application names are looked up once per bundle rather than once per item.
  private func filter(_ items: [Searchable], by filters: Filters) -> [Searchable] {
    var applications: [String: String?] = [:]

    return items.filter { item in
      var application: String?
      if filters.applications.isEmpty {
        application = nil
      } else if item.item.universalClipboard {
        application = item.application
      } else if let bundle = item.item.application {
        if let cached = applications[bundle] {
          application = cached
        } else {
          application = item.application
          applications[bundle] = application
        }
      }

      return filters.matches(kind: item.item.kind, application: application)
    }
  }

  // Takes the "type:image" and "app:safari" words out of the query and returns
  // the filters they name along with the rest of the query. A word naming an
  // unknown kind is left in the query, so a partially typed prefix still
  // searches for itself.
  private static func splitFilters(from string: String) -> (Filters, String) {
    guard string.range(of: kindPrefix, options: .caseInsensitive) != nil ||
          string.range(of: applicationPrefix, options: .caseInsensitive) != nil else {
      return (Filters(), string)
    }

    var filters = Filters()
    let words = string.split(separator: " ", omittingEmptySubsequences: false).filter { word in
      if let value = value(of: word, prefix: kindPrefix),
         let kind = HistoryItem.Kind(rawValue: value.lowercased()) {
        filters.kinds.insert(kind)
        return false
      } else if let value = value(of: word, prefix: applicationPrefix) {
        filters.applications.append(value)
        return false
      }

      return true
    }

    guard !filters.isEmpty else {
      return (filters, string)
    }

    return (filters, words.joined(separator: " ").trimmingCharacters(in: .whitespaces))
  }

  private static func value(of word: Substring, prefix: String) -> String? {
    guard word.count > prefix.count,
          word.prefix(prefix.count).lowercased() == prefix else {
      return nil
    }

    return String(word.dropFirst(prefix.count))
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
