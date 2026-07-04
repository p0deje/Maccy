import Foundation
import Fuse

/// Off-main search actor mirroring the four modes of the main-actor `Search`
/// (`exact`, `fuzzy`, `regexp`, `mixed`) on `Sendable` value types.
///
/// A throttled keystroke dispatches a search here instead of blocking the main
/// thread; results come back as `SearchMatchDTO` rather than `@MainActor`
/// `HistoryItemDecorator`, so no main-actor object crosses the boundary.
///
/// `Fuse` (threshold 0.7) and the 5,000 / 1,000-character limits are owned by
/// this actor. `Fuse` is not `Sendable`, but it lives entirely inside the actor's
/// isolation — every `createPattern` / `search` call happens here — exactly as
/// the off-main ingest actor owns a non-`Sendable` `ModelContext`. No
/// `@unchecked` or `nonisolated(unsafe)` is needed: the actor's mutual exclusion
/// is the synchronization.
///
/// Offset model: every `Range<Int>` in a returned `SearchMatchDTO.ranges` is a
/// half-open **Character (grapheme-cluster)** offset into `title`
/// (`lower..<upper`), computed via `String.distance(from:to:)` — never `NSRange`
/// or UTF-16, which would mis-highlight on emoji or combining marks. Empty regex
/// matches (`z*` → `0..<0`) are emitted as a valid empty range and resolve to
/// `startIndex..<startIndex` on the main actor (the apply side computes both
/// bounds independently via `index(startIndex, offsetBy:)`, never
/// `offsetBy: upper - 1`).
///
/// The legacy `Search` is intentionally left unchanged: `SearchTests` remain its
/// behavior gate. `SearchActor` has its own suite asserting the same four-mode
/// semantics against value types.
actor SearchActor {
  private let fuse = Fuse(threshold: 0.7)   // threshold found by trial-and-error
  private let fuzzySearchLimit = TextLimits.fuzzy
  private let regexpSearchLimit = TextLimits.regexp

  /// Searches `corpus` for `query` under `mode`, returning `SearchMatchDTO`s
  /// with the same order and semantics as `Search.search`.
  func search(
    query: String,
    within corpus: [SearchCorpusItem],
    mode: Search.Mode
  ) -> [SearchMatchDTO] {
    guard !query.isEmpty else {
      // Empty-query short-circuit: every item matches, no score, no ranges.
      return corpus.map {
        SearchMatchDTO(id: $0.id, title: $0.title, score: nil, ranges: [])
      }
    }

    switch mode {
    case .mixed:
      return mixedSearch(query: query, within: corpus)
    case .regexp:
      return regexpSearch(query: query, within: corpus)
    case .fuzzy:
      return fuzzySearch(query: query, within: corpus)
    case .exact:
      return simpleSearch(query: query, within: corpus, options: .caseInsensitive)
    }
  }

  // MARK: - Mixed

  /// Mixed search: exact → regexp → fuzzy, returning the first non-empty tier.
  private func mixedSearch(query: String, within corpus: [SearchCorpusItem]) -> [SearchMatchDTO] {
    var results = simpleSearch(query: query, within: corpus, options: .caseInsensitive)
    guard results.isEmpty else { return results }

    // The regexp tier only adds value when the query can express a pattern; a
    // metacharacter-free query is just a literal substring search that the
    // exact tier already ruled out, so skip straight to fuzzy.
    if Search.containsRegularExpressionMetacharacter(query) {
      results = regexpSearch(query: query, within: corpus)
      guard results.isEmpty else { return results }
    }

    results = fuzzySearch(query: query, within: corpus)
    guard results.isEmpty else { return results }

    return []
  }

  // MARK: - Exact

  /// Exact (substring) search across the corpus, case-insensitive.
  private func simpleSearch(
    query: String,
    within corpus: [SearchCorpusItem],
    options: NSString.CompareOptions
  ) -> [SearchMatchDTO] {
    corpus.compactMap { simpleSearch(query: query, in: $0, options: options) }
  }

  /// Exact (substring) match for one item, emitting Character offsets.
  ///
  /// Offsets are computed via `String.distance(from:to:)` — Character offsets,
  /// not `NSRange`/UTF-16 — so highlighting stays correct on emoji and combining marks.
  private func simpleSearch(
    query: String,
    in item: SearchCorpusItem,
    options: NSString.CompareOptions
  ) -> SearchMatchDTO? {
    guard let range = item.title.range(of: query, options: options, range: nil, locale: nil) else {
      return nil
    }
    let lower = item.title.distance(from: item.title.startIndex, to: range.lowerBound)
    let upper = item.title.distance(from: item.title.startIndex, to: range.upperBound)
    return SearchMatchDTO(id: item.id, title: item.title, score: nil, ranges: [lower..<upper])
  }

  // MARK: - Fuzzy

  /// Fuzzy search: Fuse pattern, 5k-character truncation guard, results sorted by score ascending.
  private func fuzzySearch(query: String, within corpus: [SearchCorpusItem]) -> [SearchMatchDTO] {
    let pattern = fuse.createPattern(from: query)
    let results: [SearchMatchDTO] = corpus.compactMap { fuzzySearch(for: pattern, in: $0) }
    return results.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
  }

  /// Scores one item against the fuzzy pattern, truncating titles beyond `fuzzySearchLimit`.
  ///
  /// The prefix is unchanged, so Character offsets against the truncated string
  /// stay valid against the full title carried in the DTO. Fuse returns inclusive
  /// ranges; they are converted to half-open Character offsets.
  private func fuzzySearch(for pattern: Fuse.Pattern?, in item: SearchCorpusItem) -> SearchMatchDTO? {
    var searchString = item.title
    if searchString.count > fuzzySearchLimit {
      // Shortcut to avoid slow search.
      searchString = searchString.shortened(to: fuzzySearchLimit)
    }

    guard let fuzzyResult = fuse.search(pattern, in: searchString) else {
      return nil
    }

    // Fuse ranges are inclusive-inclusive Character indices; emit half-open
    // Character offsets (Character, not UTF-16).
    let ranges: [Range<Int>] = fuzzyResult.ranges.map {
      $0.lowerBound..<($0.upperBound + 1)
    }
    return SearchMatchDTO(id: item.id, title: item.title, score: fuzzyResult.score, ranges: ranges)
  }

  // MARK: - Regexp

  /// Regexp search, guarded against catastrophic-backtracking patterns, with a
  /// 1k-character truncation and `firstMatch`.
  private func regexpSearch(query: String, within corpus: [SearchCorpusItem]) -> [SearchMatchDTO] {
    guard !Search.isLikelyUnsafeRegularExpression(query),
          let regex = try? NSRegularExpression(pattern: query) else {
      return []
    }
    return corpus.compactMap { regexpSearch(regex: regex, in: $0) }
  }

  /// First regex match for one item, emitting Character offsets.
  ///
  /// Offsets are computed via `String.distance(from:to:)` — Character offsets,
  /// not `NSRange`/UTF-16. An empty match (e.g. `z*` at position 0) yields
  /// `0..<0`, a valid empty range: the item still matches and resolves to
  /// `startIndex..<startIndex` (no highlight) on the main actor.
  private func regexpSearch(regex: NSRegularExpression, in item: SearchCorpusItem) -> SearchMatchDTO? {
    let limitedSearchString = item.title.shortened(to: regexpSearchLimit)
    let range = NSRange(limitedSearchString.startIndex..., in: limitedSearchString)
    guard let match = regex.firstMatch(in: limitedSearchString, range: range),
          let matchRange = Range(match.range, in: limitedSearchString) else {
      return nil
    }

    let lower = limitedSearchString.distance(
      from: limitedSearchString.startIndex, to: matchRange.lowerBound
    )
    let upper = limitedSearchString.distance(
      from: limitedSearchString.startIndex, to: matchRange.upperBound
    )
    return SearchMatchDTO(id: item.id, title: item.title, score: nil, ranges: [lower..<upper])
  }
}
