import AppKit
import Defaults
import Fuse

/// Main-actor search engine over history items, supporting exact, fuzzy, regexp, and mixed modes.
@MainActor
class Search {
  /// Search mode selected by the user.
  enum Mode: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable, Sendable {
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

    /// Short Latin-letter glyph shown in the search-field mode button
    /// (`EX`/`FZ`/`RE`/`MX`). Language-neutral; the full localized name is
    /// surfaced through ``description`` and the button's tooltip.
    var abbreviation: String {
      switch self {
      case .exact: return "EX"
      case .fuzzy: return "FZ"
      case .regexp: return "RE"
      case .mixed: return "MX"
      }
    }

    /// The next mode in declaration order, wrapping past the last case
    /// (`exact → fuzzy → regexp → mixed → exact`).
    var next: Self {
      let all = Self.allCases
      guard let index = all.firstIndex(of: self) else { return all[0] }
      return all[(index + 1) % all.count]
    }
  }

  /// A single match: the matched item, an optional fuzzy score, and the highlighted ranges.
  struct SearchResult: Equatable, Sendable {
    var score: Double?
    var object: Searchable
    var ranges: [Range<String.Index>] = []
  }

  typealias Searchable = HistoryItemDecorator

  private let fuse = Fuse(threshold: 0.7) // threshold found by trial-and-error
  private let fuzzySearchLimit = TextLimits.fuzzy
  private let regexpSearchLimit = TextLimits.regexp

  /// Returns whether `pattern` matches a known catastrophic-backtracking shape,
  /// e.g. `(a+)+$`, before it is ever compiled.
  nonisolated static func isLikelyUnsafeRegularExpression(_ pattern: String) -> Bool {
    // Reject pathologically long patterns outright — a multi-thousand-character
    // regex is far beyond any legitimate clipboard query and only risks slow
    // compilation and matching.
    guard pattern.count <= TextLimits.regexpInput else {
      return true
    }
    let nestedQuantifierPattern = #"\([^)]*([+*]|\{\d+,?\d*\})[^)]*\)([+*]|\{\d+,?\d*\})"#
    return pattern.range(of: nestedQuantifierPattern, options: .regularExpression) != nil
  }

  /// Returns whether `pattern` contains a character with special meaning in
  /// `NSRegularExpression`. A pattern without any such character can only match
  /// as a literal substring, so when the exact tier of a mixed search has
  /// already ruled it out the regexp tier cannot add anything — `mixedSearch`
  /// uses this to skip a redundant regexp pass.
  nonisolated static func containsRegularExpressionMetacharacter(_ pattern: String) -> Bool {
    pattern.rangeOfCharacter(from: CharacterSet(charactersIn: #"\.[]{}()*+?^$|"#)) != nil
  }

  /// Searches `within` for `string` under the user's configured search mode.
  ///
  /// An empty query returns every item as a match with no score and no ranges.
  func search(string: String, within: [Searchable]) -> [SearchResult] {
    guard !string.isEmpty else {
      return within.map { SearchResult(object: $0) }
    }

    switch Defaults[.searchMode] {
    case .mixed:
      return mixedSearch(string: string, within: within)
    case .regexp:
      return regexpSearch(string: string, within: within)
    case .fuzzy:
      return fuzzySearch(string: string, within: within)
    default:
      return simpleSearch(string: string, within: within, options: .caseInsensitive)
    }
  }

  /// Fuzzy search: scores each item via `Fuse` and returns matches sorted by score ascending.
  private func fuzzySearch(string: String, within: [Searchable]) -> [SearchResult] {
    let pattern = fuse.createPattern(from: string)
    let searchResults: [SearchResult] = within.compactMap { item in
      fuzzySearch(for: pattern, in: item.title, of: item)
    }
    let sortedResults = searchResults.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
    return sortedResults
  }

  /// Scores one item against the fuzzy pattern, truncating titles beyond `fuzzySearchLimit` to keep search fast.
  private func fuzzySearch(
    for pattern: Fuse.Pattern?,
    in searchString: String,
    of item: Searchable
  ) -> SearchResult? {
    var searchString = searchString
    if searchString.count > fuzzySearchLimit {
      // shortcut to avoid slow search
      let stopIndex = searchString.index(searchString.startIndex, offsetBy: fuzzySearchLimit)
      searchString = "\(searchString[..<stopIndex])"
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

  /// Exact (substring) search across all items.
  private func simpleSearch(
    string: String,
    within: [Searchable],
    options: NSString.CompareOptions
  ) -> [SearchResult] {
    return within.compactMap { simpleSearch(for: string, in: $0.title, of: $0, options: options) }
  }

  /// Exact (substring) match for one item.
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

  /// Mixed search: exact → regexp → fuzzy, returning the first non-empty tier.
  private func mixedSearch(string: String, within: [Searchable]) -> [SearchResult] {
    var results = simpleSearch(string: string, within: within, options: .caseInsensitive)
    guard results.isEmpty else {
      return results
    }

    // The regexp tier only adds value when the query can express a pattern; a
    // metacharacter-free query is just a literal substring search that the
    // exact tier already ruled out, so skip straight to fuzzy.
    if Self.containsRegularExpressionMetacharacter(string) {
      results = regexpSearch(string: string, within: within)
      guard results.isEmpty else {
        return results
      }
    }

    results = fuzzySearch(string: string, within: within)
    guard results.isEmpty else {
      return results
    }

    return []
  }

  /// Regexp search, guarded against catastrophic-backtracking patterns.
  private func regexpSearch(string: String, within: [Searchable]) -> [SearchResult] {
    guard !Self.isLikelyUnsafeRegularExpression(string),
          let regex = try? NSRegularExpression(pattern: string) else {
      return []
    }

    return within.compactMap { item in
      regexpSearch(regex: regex, in: item.title, of: item)
    }
  }

  /// First regex match for one item, searching only the first `regexpSearchLimit` characters.
  private func regexpSearch(regex: NSRegularExpression, in searchString: String, of item: Searchable) -> SearchResult? {
    let limitedSearchString = searchString.shortened(to: regexpSearchLimit)
    let range = NSRange(limitedSearchString.startIndex..., in: limitedSearchString)
    guard let match = regex.firstMatch(in: limitedSearchString, range: range),
          let matchRange = Range(match.range, in: limitedSearchString) else {
      return nil
    }

    return SearchResult(object: item, ranges: [matchRange])
  }
}
