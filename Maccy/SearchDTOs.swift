import Foundation

/// Sendable corpus projection for off-main search (BS-5).
///
/// `HistoryItemDecorator` is `@MainActor` (its `title` reads/writes main-actor
/// state), so the decorator cannot cross to `SearchActor`. The main actor
/// snapshots each visible item into this value type — only the id (a
/// caller-chosen `UUID`) and the searchable `title` leave the main actor. `id`
/// is opaque to the actor; the caller owns the id→decorator association and
/// resolves it back on the main actor in the apply callback (a
/// `[UUID: HistoryItemDecorator]` map built on main at snapshot time, touched
/// only in the `@MainActor` apply callback — never sent to the actor).
struct SearchCorpusItem: Equatable, Hashable, Sendable {
  let id: UUID
  let title: String
}

/// Sendable search result returned by `SearchActor` (BS-5).
///
/// - `id`: echoes the matched `SearchCorpusItem.id`. The actor never reorders
///   by id; fuzzy reorders by `score`, exact/regexp filter preserving corpus
///   order — so the caller correlates results back to decorators by `id`, not
///   by array position.
/// - `title`: the title snapshot at search time. The apply callback MUST
///   highlight only when `decorator.title == dto.title`; a mismatch means the
///   item's title changed (or the item was replaced) while the search was in
///   flight, so offsets computed against the old title would mis-highlight or
///   trap. This DTO field exists precisely to enable that staleness guard.
/// - `score`: fuzzy match score (lower = better); `nil` for exact/regexp and
///   for the empty-query "match all" case.
/// - `ranges`: half-open `Range<Int>` of **Character (grapheme-cluster)
///   offsets** into `title` (`lower..<upper`), NOT `NSRange`/UTF-16 (bug-2 fix).
///   Computed via `String.distance(from:to:)` on the way out and resolved via
///   `String.index(startIndex, offsetBy:)` on the way in. A zero-length range
///   (`lower == upper`, e.g. an empty regex match `z*` at position 0 → `0..<0`,
///   bug-5 fix) is valid and resolves to `startIndex..<startIndex` (no visible
///   highlight); the apply side computes both bounds independently and never
///   assumes `lower < upper` (never `offsetBy: upper - 1`).
struct SearchMatchDTO: Equatable, Sendable {
  let id: UUID
  let title: String
  let score: Double?
  let ranges: [Range<Int>]
}
