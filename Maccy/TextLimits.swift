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
  /// Longest regexp pattern (in graphemes) accepted for compilation. Anything
  /// longer is rejected outright — far beyond any legitimate clipboard query
  /// and only a compile/match cost risk.
  static let regexpInput = 2_000
}
