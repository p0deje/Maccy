/// Single source of truth for the truncation lengths used across the search
/// pipeline, so the match decision and the highlight renderer always slice the
/// same window of a title.
///
/// A mismatch — the search scanning one length and the highlight rendering a
/// shorter one — silently drops highlights for any match past the shorter
/// length, because the apply side's `AttributedString.Index(within:)` returns
/// `nil` for offsets beyond the rendered window. Centralizing the constants
/// here keeps the match and render windows aligned.
enum TextLimits {
  /// Maximum graphemes retained when generating a title preview.
  static let titlePreview = 1_000
  /// Grapheme window the highlight renderer keeps. Matches ``titlePreview`` so
  /// a hit anywhere the search scanned stays renderable.
  static let highlight = 1_000
  /// Most graphemes of a title the fuzzy match scans.
  static let fuzzy = 5_000
  /// Most graphemes of a title the regexp match scans.
  static let regexp = 1_000
  /// Most graphemes of an item's body that the search actor keeps and scans.
  /// Bounding the body keeps the actor's corpus and the per-keystroke match
  /// cost finite for very large clips; a match beyond this window is not found.
  /// This is also the default for the user-configurable
  /// ``Defaults.Keys/searchBodyLimit``.
  static let searchBody = 32_000
  /// Inclusive bounds for the configurable body-scan cap. The stored
  /// ``Defaults.Keys/searchBodyLimit`` value is clamped to this range at read
  /// time so an out-of-range setting cannot starve search (too small) or let a
  /// single clip's body dominate corpus memory (too large).
  static let searchBodyMin = 1_000
  static let searchBodyMax = 256_000

  /// Returns `limit` clamped to the configurable body-scan range.
  static func clampedSearchBody(_ limit: Int) -> Int {
    min(max(limit, searchBodyMin), searchBodyMax)
  }
  /// Longest regexp pattern (in graphemes) accepted for compilation. Anything
  /// longer is rejected outright — far beyond any legitimate clipboard query
  /// and only a compile/match cost risk.
  static let regexpInput = 2_000
}
