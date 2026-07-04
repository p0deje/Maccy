import XCTest
@testable import Maccy

/// Empirical gate for the off-main search's highlight-offset semantics.
///
/// The apply side resolves every `SearchMatchDTO.ranges` entry through
/// `String.index(offsetBy:)` — Character (grapheme) steps. A match range is
/// therefore correct only if the search produced it as a Character offset.
/// Exact and regexp modes compute offsets via `String.distance(from:to:)`,
/// which is unambiguously Character-based; the fuzzy path forwards `Fuse`'s
/// raw ranges directly. These tests pin empirically which offset model each
/// path uses by way of an emoji (😀 = one grapheme, two UTF-16 code units),
/// which separates the two models.
final class SearchHighlightIndexTests: XCTestCase {
  /// Control: exact substring search must produce the Character offset of the
  /// 'y' in "x😀y" (x = 0, 😀 = 1, y = 2).
  func test_exactRange_emoji_isGraphemeOffset() async {
    let actor = SearchActor()
    let corpus = [SearchCorpusItem(id: UUID(), title: "x😀y", body: "")]

    let results = await actor.search(query: "y", within: corpus, mode: .exact)

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(
      results[0].ranges.first,
      2..<3,
      "exact 'y' in 'x😀y' must be the grapheme offset 2"
    )
  }

  /// Probe of the fuzzy path's offset model: fuzzy 'y' in "x😀y". If `Fuse`
  /// returns Character offsets the range is 2..<3 (lands on 'y'); if it
  /// returns UTF-16 code-unit offsets the range is 3..<4 (lands past the
  /// emoji's surrogate pair). A pass means the fuzzy path is already
  /// grapheme-correct; a fail means it needs a UTF-16-to-grapheme conversion
  /// before the apply side's `index(offsetBy:)`.
  func test_fuzzyRange_emoji_landsOnCorrectGrapheme() async {
    let actor = SearchActor()
    let corpus = [SearchCorpusItem(id: UUID(), title: "x😀y", body: "")]

    let results = await actor.search(query: "y", within: corpus, mode: .fuzzy)

    XCTAssertEqual(results.count, 1, "fuzzy 'y' should match 'x😀y'")
    XCTAssertEqual(
      results[0].ranges.first,
      2..<3,
      "Fuse fuzzy offset for 'y' in 'x😀y' must be the grapheme offset (2), not UTF-16 (3)"
    )
  }
}
