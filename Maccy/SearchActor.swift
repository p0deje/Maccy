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

  /// The owned corpus, keyed by item id, plus the `all`-order sequence of ids
  /// so exact/regexp results come back in the same order the list shows. The
  /// main actor maintains this incrementally on add/remove/clear; a keystroke
  /// then dispatches only the query and mode — not a rebuilt corpus projection.
  private var corpusByID: [ItemID: SearchCorpusItem] = [:]
  private var order: [ItemID] = []

  /// Searches the owned corpus for `query` under `mode`, projecting it in
  /// `all` order and delegating to the pure ``search(query:within:mode:)``.
  func search(query: String, mode: Search.Mode) -> [SearchMatchDTO] {
    let corpus = order.compactMap { corpusByID[$0] }
    return search(query: query, within: corpus, mode: mode)
  }

  // MARK: - Corpus ownership

  /// Rebuilds the corpus from `entries` (in `all` order). Used at load, after a
  /// clear leaves survivors, and as the full-reconcile fallback.
  func replaceCorpus(_ entries: [SearchCorpusItem]) {
    corpusByID.removeAll(keepingCapacity: true)
    order = entries.map(\.id)
    for entry in entries {
      corpusByID[entry.id] = entry
    }
  }

  /// Inserts `entry` at `position` (the index its decorator occupies in `all`),
  /// removing any prior entry that shares its id first. `position` is clamped
  /// to the corpus bounds so a racy ship can't trap.
  func insert(_ entry: SearchCorpusItem, at position: Int) {
    if corpusByID[entry.id] != nil {
      remove([entry.id])
    }
    let clamped = max(0, min(position, order.count))
    order.insert(entry.id, at: clamped)
    corpusByID[entry.id] = entry
  }

  /// Drops every entry whose id is in `ids`.
  func remove(_ ids: [ItemID]) {
    guard !ids.isEmpty else { return }
    let idSet = Set(ids)
    order.removeAll { idSet.contains($0) }
    for id in ids {
      corpusByID.removeValue(forKey: id)
    }
  }

  /// Empties the corpus.
  func clearCorpus() {
    corpusByID.removeAll()
    order.removeAll()
  }

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

  /// Exact (substring) match for one item, emitting Character offsets. Scans the
  /// title first; if the title does not match, scans the body (full-text) so a
  /// clip whose title does not contain the query still surfaces when its content
  /// does. A title match is preferred (its offsets index into the displayed
  /// title); a body match carries `inBody: true` with offsets into the body.
  ///
  /// Offsets are computed via `String.distance(from:to:)` — Character offsets,
  /// not `NSRange`/UTF-16 — so highlighting stays correct on emoji and combining marks.
  private func simpleSearch(
    query: String,
    in item: SearchCorpusItem,
    options: NSString.CompareOptions
  ) -> SearchMatchDTO? {
    if let range = item.title.range(of: query, options: options, range: nil, locale: nil) {
      let lower = item.title.distance(from: item.title.startIndex, to: range.lowerBound)
      let upper = item.title.distance(from: item.title.startIndex, to: range.upperBound)
      return SearchMatchDTO(id: item.id, title: item.title, score: nil, ranges: [lower..<upper])
    }
    guard !item.body.isEmpty,
          let range = item.body.range(of: query, options: options, range: nil, locale: nil) else {
      return nil
    }
    let lower = item.body.distance(from: item.body.startIndex, to: range.lowerBound)
    let upper = item.body.distance(from: item.body.startIndex, to: range.upperBound)
    return SearchMatchDTO(id: item.id, title: item.title, score: nil, ranges: [lower..<upper], inBody: true)
  }

  // MARK: - Fuzzy

  /// Fuzzy search: Fuse pattern, `fuzzySearchLimit` truncation guard. Results
  /// are ordered title matches first, then body matches — within each bucket by
  /// score ascending. Fuse scores are not normalized across haystack length
  /// (a title vs a body prefix), so a single cross-field score sort would order
  /// arbitrarily; bucketing keeps title hits above content-only hits.
  private func fuzzySearch(query: String, within corpus: [SearchCorpusItem]) -> [SearchMatchDTO] {
    let pattern = fuse.createPattern(from: query)
    let results: [SearchMatchDTO] = corpus.compactMap { fuzzySearch(for: pattern, in: $0) }
    return results.sorted {
      if $0.inBody != $1.inBody { return !$0.inBody }
      return ($0.score ?? 0) < ($1.score ?? 0)
    }
  }

  /// Scores one item against the fuzzy pattern, scanning the title first and
  /// falling back to the body prefix when the title does not match — mirroring
  /// ``simpleSearch(query:in:options:)``. A title match carries title-relative
  /// offsets; a body match carries body-relative offsets and `inBody: true`.
  ///
  /// Both fields are truncated to `fuzzySearchLimit` (grapheme-safe) so the Fuse
  /// dynamic-programming cost stays bounded. Fuse returns inclusive Character
  /// ranges; they are converted to half-open Character offsets.
  private func fuzzySearch(for pattern: Fuse.Pattern?, in item: SearchCorpusItem) -> SearchMatchDTO? {
    var titleString = item.title
    if titleString.count > fuzzySearchLimit {
      titleString = titleString.shortened(to: fuzzySearchLimit)
    }
    if let titleResult = fuse.search(pattern, in: titleString) {
      return SearchMatchDTO(
        id: item.id,
        title: item.title,
        score: titleResult.score,
        ranges: titleResult.ranges.map { $0.lowerBound..<($0.upperBound + 1) }
      )
    }
    guard !item.body.isEmpty else { return nil }
    let bodyString = item.body.shortened(to: fuzzySearchLimit)
    guard let bodyResult = fuse.search(pattern, in: bodyString) else { return nil }
    return SearchMatchDTO(
      id: item.id,
      title: item.title,
      score: bodyResult.score,
      ranges: bodyResult.ranges.map { $0.lowerBound..<($0.upperBound + 1) },
      inBody: true
    )
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

  /// First regex match for one item, emitting Character offsets. Scans the title
  /// first; if it does not match, scans the body (full-text), mirroring
  /// ``simpleSearch(query:in:options:)``. A title match is preferred; a body
  /// match carries `inBody: true` with offsets into the body.
  ///
  /// Offsets are computed via `String.distance(from:to:)` — Character offsets,
  /// not `NSRange`/UTF-16. An empty match (e.g. `z*` at position 0) yields
  /// `0..<0`, a valid empty range: the item still matches and resolves to
  /// `startIndex..<startIndex` (no highlight) on the main actor.
  private func regexpSearch(regex: NSRegularExpression, in item: SearchCorpusItem) -> SearchMatchDTO? {
    let limitedTitle = item.title.shortened(to: regexpSearchLimit)
    let titleRange = NSRange(limitedTitle.startIndex..., in: limitedTitle)
    if let match = regex.firstMatch(in: limitedTitle, range: titleRange),
       let matchRange = Range(match.range, in: limitedTitle) {
      let lower = limitedTitle.distance(from: limitedTitle.startIndex, to: matchRange.lowerBound)
      let upper = limitedTitle.distance(from: limitedTitle.startIndex, to: matchRange.upperBound)
      return SearchMatchDTO(id: item.id, title: item.title, score: nil, ranges: [lower..<upper])
    }
    guard !item.body.isEmpty else {
      return nil
    }
    let bodyRange = NSRange(item.body.startIndex..., in: item.body)
    guard let match = regex.firstMatch(in: item.body, range: bodyRange),
          let matchRange = Range(match.range, in: item.body) else {
      return nil
    }
    let lower = item.body.distance(from: item.body.startIndex, to: matchRange.lowerBound)
    let upper = item.body.distance(from: item.body.startIndex, to: matchRange.upperBound)
    return SearchMatchDTO(id: item.id, title: item.title, score: nil, ranges: [lower..<upper], inBody: true)
  }
}
