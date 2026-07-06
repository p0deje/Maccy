import Foundation

/// `Sendable` corpus projection for off-main search.
///
/// `HistoryItemDecorator` is `@MainActor` (its `title` reads and writes
/// main-actor state), so the decorator cannot cross to `SearchActor`. The main
/// actor projects each visible item into this value type — only the id (a
/// caller-chosen `UUID`), the searchable `title`, and the searchable `body`
/// (the item's full text, capped) leave the main actor. `id` is opaque to the
/// actor; the caller owns the id-to-decorator association and resolves it back
/// on the main actor in the apply callback.
///
/// The actor owns its corpus of these entries and maintains it incrementally on
/// add/remove/clear, so a keystroke no longer rebuilds the projection on the
/// main actor — it dispatches only the query and mode.
struct SearchCorpusItem: Equatable, Hashable, Sendable {
  let id: UUID
  let title: String
  let body: String
}

/// `Sendable` search result returned by `SearchActor`.
///
/// - `id`: echoes the matched `SearchCorpusItem.id`. The actor never reorders by
///   id; fuzzy reorders by `score`, exact/regexp filter preserving corpus order,
///   so the caller correlates results back to decorators by `id`, not by array
///   position.
/// - `title`: the title snapshot at search time. The apply callback must
///   highlight only when `decorator.title == dto.title`; a mismatch means the
///   item's title changed (or the item was replaced) while the search was in
///   flight, so offsets computed against the old title would mis-highlight or
///   trap. This field exists precisely to enable that staleness guard.
/// - `score`: fuzzy match score (lower is better); `nil` for exact/regexp and
///   for the empty-query "match all" case.
/// - `ranges`: half-open `Range<Int>` of **Character (grapheme-cluster) offsets**
///   (`lower..<upper`), not `NSRange`/UTF-16. Computed via
///   `String.distance(from:to:)` on the way out and resolved via
///   `String.index(startIndex, offsetBy:)` on the way in. A zero-length range
///   (`lower == upper`, e.g. an empty regex match `z*` at position 0 → `0..<0`)
///   is valid and resolves to `startIndex..<startIndex` (no visible highlight);
///   the apply side computes both bounds independently and never assumes
///   `lower < upper` (never `offsetBy: upper - 1`).
/// - `inBody`: when false (the default) `ranges` index into the item's `title`
///   and the apply side title-highlights them. When true, `ranges` index into
///   the item's `body` (the capped scan window) — a full-text match beyond the
///   title — and the apply side must NOT title-highlight (the offsets are
///   body-relative); preview-pane highlight is applied separately.
struct SearchMatchDTO: Equatable, Sendable {
  let id: UUID
  let title: String
  let score: Double?
  let ranges: [Range<Int>]
  let inBody: Bool

  init(
    id: UUID,
    title: String,
    score: Double?,
    ranges: [Range<Int>],
    inBody: Bool = false
  ) {
    self.id = id
    self.title = title
    self.score = score
    self.ranges = ranges
    self.inBody = inBody
  }
}
