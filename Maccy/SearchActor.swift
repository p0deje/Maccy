import Foundation
import Fuse

/// Off-main search actor (BS-5). Mirrors the four modes of the legacy
/// `@MainActor Search` (`exact` / `fuzzy` / `regexp` / `mixed`) byte-for-byte,
/// but operates on `Sendable` `SearchCorpusItem` / `SearchMatchDTO` value types
/// instead of `@MainActor` `HistoryItemDecorator`, so a throttled keystroke no
/// longer blocks the main thread.
///
/// `Fuse` (threshold 0.7) and the 5k / 1k limits are owned by this actor.
/// `Fuse` is not `Sendable`, but it lives entirely inside the actor's isolation
/// — every `createPattern` / `search` call happens here — exactly as
/// `BackgroundClipboardIngestor` owns a non-`Sendable` `ModelContext`. No
/// `@unchecked` / `nonisolated(unsafe)` is needed: the actor's mutual exclusion
/// is the synchronization.
///
/// Offset model (bug-2 fix): every `Range<Int>` in a returned
/// `SearchMatchDTO.ranges` is a half-open **Character (grapheme-cluster)**
/// offset into `title` (`lower..<upper`), computed via
/// `String.distance(from:to:)` — never `NSRange` / UTF-16, which would
/// mis-highlight on emoji / combining marks. Empty regex matches (`z*` →
/// `{0,0}`) are emitted as `0..<0` (bug-5 fix) and resolve to
/// `startIndex..<startIndex` on the main actor (the apply side computes both
/// bounds independently via `index(startIndex, offsetBy:)`, never
/// `offsetBy: upper - 1`).
///
/// The legacy `Search.search` is intentionally left UNCHANGED: `SearchTests`
/// remain the byte-for-byte behavior gate for it. `SearchActor` has its own
/// test suite (`SearchActorTests`) asserting the same four-mode semantics
/// against value types.
actor SearchActor {
  private let fuse = Fuse(threshold: 0.7)   // threshold found by trial-and-error (mirrors Search.swift:37)
  private let fuzzySearchLimit = 5_000       // mirrors Search.swift:38
  private let regexpSearchLimit = 1_000      // mirrors Search.swift:39

  /// Searches `corpus` for `query` under `mode`, returning `SearchMatchDTO`s
  /// in the same order/semantics as the legacy `Search.search`.
  func search(
    query: String,
    within corpus: [SearchCorpusItem],
    mode: Search.Mode
  ) -> [SearchMatchDTO] {
    guard !query.isEmpty else {
      // Mirrors Search.search empty-query short-circuit (Search.swift:48-50):
      // every item matches, no score, no ranges.
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

  /// Mirrors `Search.mixedSearch` (Search.swift:123-140): simple → regexp →
  /// fuzzy, returning the first non-empty tier.
  private func mixedSearch(query: String, within corpus: [SearchCorpusItem]) -> [SearchMatchDTO] {
    var results = simpleSearch(query: query, within: corpus, options: .caseInsensitive)
    guard results.isEmpty else { return results }

    results = regexpSearch(query: query, within: corpus)
    guard results.isEmpty else { return results }

    results = fuzzySearch(query: query, within: corpus)
    guard results.isEmpty else { return results }

    return []
  }

  // MARK: - Exact

  /// Mirrors `Search.simpleSearch` (Search.swift:102-121), caseInsensitive.
  private func simpleSearch(
    query: String,
    within corpus: [SearchCorpusItem],
    options: NSString.CompareOptions
  ) -> [SearchMatchDTO] {
    corpus.compactMap { simpleSearch(query: query, in: $0, options: options) }
  }

  private func simpleSearch(
    query: String,
    in item: SearchCorpusItem,
    options: NSString.CompareOptions
  ) -> SearchMatchDTO? {
    guard let range = item.title.range(of: query, options: options, range: nil, locale: nil) else {
      return nil
    }
    // Character (grapheme) offsets via distance — NOT NSRange/UTF-16 (bug-2 fix).
    let lower = item.title.distance(from: item.title.startIndex, to: range.lowerBound)
    let upper = item.title.distance(from: item.title.startIndex, to: range.upperBound)
    return SearchMatchDTO(id: item.id, title: item.title, score: nil, ranges: [lower..<upper])
  }

  // MARK: - Fuzzy

  /// Mirrors `Search.fuzzySearch` (Search.swift:64-100): Fuse pattern, 5k-char
  /// truncation guard, results sorted by score ascending.
  private func fuzzySearch(query: String, within corpus: [SearchCorpusItem]) -> [SearchMatchDTO] {
    let pattern = fuse.createPattern(from: query)
    let results: [SearchMatchDTO] = corpus.compactMap { fuzzySearch(for: pattern, in: $0) }
    return results.sorted(by: { ($0.score ?? 0) < ($1.score ?? 0) })
  }

  private func fuzzySearch(for pattern: Fuse.Pattern?, in item: SearchCorpusItem) -> SearchMatchDTO? {
    var searchString = item.title
    if searchString.count > fuzzySearchLimit {
      // Shortcut to avoid slow search (mirrors Search.swift:79-83). The prefix
      // is unchanged, so Character offsets against the truncated string stay
      // valid against the full title carried in the DTO.
      searchString = searchString.shortened(to: fuzzySearchLimit)
    }

    guard let fuzzyResult = fuse.search(pattern, in: searchString) else {
      return nil
    }

    // Fuse ranges are inclusive-inclusive Character indices (Search.swift:89-95
    // converts via index(offsetBy: lower)..<index(offsetBy: upper+1)). Emit
    // half-open Character offsets lower..<(upper+1) (bug-2 fix: Character,
    // not UTF-16).
    let ranges: [Range<Int>] = fuzzyResult.ranges.map {
      $0.lowerBound..<($0.upperBound + 1)
    }
    return SearchMatchDTO(id: item.id, title: item.title, score: fuzzyResult.score, ranges: ranges)
  }

  // MARK: - Regexp

  /// Mirrors `Search.regexpSearch` (Search.swift:142-162): unsafe-regex guard,
  /// 1k-char truncation, `firstMatch`. Reuses the legacy nonisolated static
  /// `Search.isLikelyUnsafeRegularExpression`.
  private func regexpSearch(query: String, within corpus: [SearchCorpusItem]) -> [SearchMatchDTO] {
    guard !Search.isLikelyUnsafeRegularExpression(query),
          let regex = try? NSRegularExpression(pattern: query) else {
      return []
    }
    return corpus.compactMap { regexpSearch(regex: regex, in: $0) }
  }

  private func regexpSearch(regex: NSRegularExpression, in item: SearchCorpusItem) -> SearchMatchDTO? {
    let limitedSearchString = item.title.shortened(to: regexpSearchLimit)
    let range = NSRange(limitedSearchString.startIndex..., in: limitedSearchString)
    guard let match = regex.firstMatch(in: limitedSearchString, range: range),
          let matchRange = Range(match.range, in: limitedSearchString) else {
      return nil
    }

    // Character (grapheme) offsets via distance (bug-2 fix). An empty match
    // (`z*` at position 0 → match.range length 0 → matchRange
    // startIndex..<startIndex) yields `0..<0` — a valid empty range (bug-5
    // fix): the item still matches, and resolves to startIndex..<startIndex
    // (no highlight) on the main actor, matching legacy behavior.
    let lower = limitedSearchString.distance(
      from: limitedSearchString.startIndex, to: matchRange.lowerBound
    )
    let upper = limitedSearchString.distance(
      from: limitedSearchString.startIndex, to: matchRange.upperBound
    )
    return SearchMatchDTO(id: item.id, title: item.title, score: nil, ranges: [lower..<upper])
  }
}
