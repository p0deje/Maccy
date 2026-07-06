import XCTest
@testable import Maccy

/// Behavior tests for the off-main `SearchActor`. The legacy `SearchTests`
/// remain the byte-for-byte gate for `Search.search`; these tests assert the
/// same four-mode semantics against `Sendable` value types, plus the two
/// soundness properties the actor owns: grapheme (Character) match offsets, and
/// empty regex matches resolving to a valid zero-length range.
final class SearchActorTests: XCTestCase {
  private let searchActor = SearchActor()

  /// Builds a deterministic corpus item whose id encodes `number`, so `ids(_:)`
  /// can recover the original integer from the returned matches.
  private func item(_ number: Int, _ title: String, body: String = "") -> SearchCorpusItem {
    let suffix = String(format: "%012d", number)
    return SearchCorpusItem(id: UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!, title: title, body: body)
  }

  /// Extracts the trailing integer each result id encodes, in match order.
  private func ids(_ results: [SearchMatchDTO]) -> [Int] {
    results.compactMap { Int($0.id.uuidString.suffix(12)) }
  }

  // MARK: - Empty query

  /// An empty query returns every item, with no scores and no highlight ranges.
  func testEmptyQueryReturnsAllItemsWithNoRanges() async {
    let corpus = [item(1, "foo bar"), item(2, "baz")]
    for mode in Search.Mode.allCases {
      let results = await searchActor.search(query: "", within: corpus, mode: mode)
      XCTAssertEqual(ids(results), [1, 2], "mode \(mode)")
      XCTAssertTrue(results.allSatisfy { $0.score == nil && $0.ranges.isEmpty }, "mode \(mode)")
      XCTAssertEqual(results.map(\.title), ["foo bar", "baz"], "mode \(mode)")
    }
  }

  // MARK: - Exact (grapheme offsets)

  /// Exact match offsets are case-insensitive and point at the first matching
  /// grapheme in each title.
  func testExactSearchCaseInsensitiveOffsets() async {
    let corpus = [item(1, "foo bar baz"),
                  item(2, "foo bar zaz"),
                  item(3, "xxx yyy zzz")]
    let results = await searchActor.search(query: "z", within: corpus, mode: .exact)
    XCTAssertEqual(ids(results), [1, 2, 3])
    XCTAssertEqual(results[0].ranges, [10..<11]) // 'z' in "foo bar baz"
    XCTAssertEqual(results[1].ranges, [8..<9])   // first 'z' in "foo bar zaz"
    XCTAssertEqual(results[2].ranges, [8..<9])   // first 'z' in "xxx yyy zzz"
  }

  /// Exact search matches regardless of letter case.
  func testExactSearchIsCaseInsensitive() async {
    let corpus = [item(1, "foo bar")]
    let results = await searchActor.search(query: "FOO", within: corpus, mode: .exact)
    XCTAssertEqual(results, [SearchMatchDTO(id: item(1, "foo bar").id, title: "foo bar", score: nil, ranges: [0..<3])])
  }

  /// An exact query that matches nothing returns an empty result.
  func testExactSearchNoMatchReturnsEmpty() async {
    let corpus = [item(1, "foo bar"), item(2, "baz")]
    let results = await searchActor.search(query: "nope", within: corpus, mode: .exact)
    XCTAssertTrue(results.isEmpty)
  }

  /// Match offsets are grapheme (Character) counts, not UTF-16 code-unit counts.
  /// `👍` is one grapheme but two UTF-16 code units, so a correct grapheme model
  /// yields `1..<2` where a UTF-16/NSRange model would yield `1..<3`.
  func testExactOffsetsAreCharacterNotUTF16() async {
    let corpus = [item(1, "a👍b")]
    let results = await searchActor.search(query: "👍", within: corpus, mode: .exact)
    XCTAssertEqual(results, [SearchMatchDTO(id: item(1, "a👍b").id, title: "a👍b", score: nil, ranges: [1..<2])])
  }

  /// The regexp path produces the same grapheme-offset guarantee as the exact
  /// path (NSRange converted to a Swift `Range` and measured in Characters).
  func testRegexpOffsetsAreCharacterNotUTF16() async {
    let corpus = [item(1, "a👍b")]
    let results = await searchActor.search(query: "👍", within: corpus, mode: .regexp)
    XCTAssertEqual(results, [SearchMatchDTO(id: item(1, "a👍b").id, title: "a👍b", score: nil, ranges: [1..<2])])
  }

  // MARK: - Regexp (empty match handling)

  /// Regexp matches report the half-open grapheme range of each match.
  func testRegexpSearchOffsets() async {
    let corpus = [item(1, "foo bar baz")]
    let baMatches = await searchActor.search(query: "ba", within: corpus, mode: .regexp)
    XCTAssertEqual(
      baMatches,
      [SearchMatchDTO(id: item(1, "foo bar baz").id, title: "foo bar baz", score: nil, ranges: [4..<6])]
    )

    let span = await searchActor.search(query: "ba.*z", within: corpus, mode: .regexp)
    XCTAssertEqual(
      span,
      [SearchMatchDTO(id: item(1, "foo bar baz").id, title: "foo bar baz", score: nil, ranges: [4..<11])]
    )
  }

  /// A zero-length regex match (`z*` against a string with no `z`) keeps the
  /// item as a match and reports a valid empty range `0..<0` (resolving to
  /// `startIndex..<startIndex`). No highlight is applied. A naive implementation
  /// would drop the item, trap on `upperBound - 1`, or fail to convert a
  /// zero-length NSRange into a Swift Range.
  func testRegexpEmptyMatchIsZeroLengthRange() async {
    let corpus = [item(1, "abc")]
    let results = await searchActor.search(query: "z*", within: corpus, mode: .regexp)
    XCTAssertEqual(results, [SearchMatchDTO(id: item(1, "abc").id, title: "abc", score: nil, ranges: [0..<0])])
  }

  /// Patterns that would be catastrophic to evaluate are rejected, yielding an
  /// empty result rather than hanging.
  func testRegexpUnsafePatternReturnsEmpty() async {
    let corpus = [item(1, "aaaa")]
    let results = await searchActor.search(query: "(a+)+$", within: corpus, mode: .regexp)
    XCTAssertTrue(results.isEmpty)
  }

  /// An invalid regex is treated as matching nothing rather than trapping.
  func testRegexpInvalidPatternReturnsEmpty() async {
    let corpus = [item(1, "foo")]
    let results = await searchActor.search(query: "(", within: corpus, mode: .regexp)
    XCTAssertTrue(results.isEmpty)
  }

  // MARK: - Fuzzy

  /// Fuzzy matching returns the matched item with a non-nil score and valid
  /// half-open grapheme ranges into the title.
  func testFuzzyReturnsMatchedItemWithScore() async {
    let corpus = [item(1, "foo bar"), item(2, "xyz")]
    let results = await searchActor.search(query: "fb", within: corpus, mode: .fuzzy)
    XCTAssertEqual(ids(results), [1])
    XCTAssertNotNil(results.first?.score)
    // All ranges are valid half-open Character offsets into the title.
    let title = "foo bar"
    XCTAssertTrue(
      results.first?.ranges.allSatisfy {
        $0.lowerBound >= 0 && $0.upperBound <= title.count && $0.lowerBound <= $0.upperBound
      } ?? false
    )
  }

  /// Fuzzy results are ordered by ascending score (best matches first).
  func testFuzzySortsByScoreAscending() async {
    let corpus = [item(1, "axx"), item(2, "x")]
    let results = await searchActor.search(query: "x", within: corpus, mode: .fuzzy)
    XCTAssertEqual(ids(results), [2, 1]) // perfect match "x" (score 0) first
    let scores = results.compactMap { $0.score }
    XCTAssertEqual(scores.count, 2)
    XCTAssertTrue(scores[0] <= scores[1])
  }

  // MARK: - Mixed

  /// Mixed mode prefers the simpler exact tier when it already matches.
  func testMixedSimpleTierWins() async {
    let corpus = [item(1, "foo bar"), item(2, "baz")]
    let results = await searchActor.search(query: "foo", within: corpus, mode: .mixed)
    XCTAssertEqual(results, [SearchMatchDTO(id: item(1, "foo bar").id, title: "foo bar", score: nil, ranges: [0..<3])])
  }

  /// When the exact tier does not match, mixed mode falls through to regexp.
  func testMixedFallsThroughToRegexp() async {
    let corpus = [item(1, "foo"), item(2, "fxo"), item(3, "bar")]
    let results = await searchActor.search(query: "f.o", within: corpus, mode: .mixed)
    XCTAssertEqual(ids(results), [1, 2])
    XCTAssertTrue(results.allSatisfy { $0.ranges == [0..<3] })
  }

  /// When neither exact nor regexp matches, mixed mode falls through to fuzzy.
  func testMixedFallsThroughToFuzzy() async {
    let corpus = [item(1, "foo bar"), item(2, "xyz")]
    let results = await searchActor.search(query: "fb", within: corpus, mode: .mixed)
    XCTAssertEqual(ids(results), [1])
    XCTAssertNotNil(results.first?.score)
  }

  /// Mixed mode surfaces a clip whose body (not title) contains the query via
  /// the exact tier — a full-text match under the default mode.
  func testMixedFindsBodyMatchViaExactTier() async {
    let corpus = [item(1, "zzz", body: "the needle")]
    let results = await searchActor.search(query: "needle", within: corpus, mode: .mixed)

    XCTAssertEqual(ids(results), [1])
    XCTAssertEqual(results.first?.inBody, true)
    XCTAssertNil(results.first?.score)
  }

  /// Mixed mode surfaces a clip whose body fuzzy-matches (and does not match the
  /// exact or regexp tiers) via the fuzzy tier — full-text fuzzy recall under
  /// the default mode. The regexp tier is skipped because the query has no
  /// regular-expression metacharacter.
  func testMixedFindsBodyMatchViaFuzzyTier() async {
    let corpus = [item(1, "zzz", body: "foo bar")]
    let results = await searchActor.search(query: "fb", within: corpus, mode: .mixed)

    XCTAssertEqual(ids(results), [1])
    XCTAssertEqual(results.first?.inBody, true)
    XCTAssertNotNil(results.first?.score)
  }
}
