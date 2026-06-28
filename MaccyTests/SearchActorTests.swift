import XCTest
@testable import Maccy

/// Behavior tests for `SearchActor` (BS-5). The legacy `SearchTests` remain the
/// byte-for-byte gate for `Search.search`; these tests assert the same four-mode
/// semantics against `Sendable` value types, plus the two soundness fixes the
/// actor owns: Character (grapheme) offsets (bug 2) and regex empty-match →
/// `0..<0` (bug 5).
final class SearchActorTests: XCTestCase {
  private let searchActor = SearchActor()

  /// Deterministic corpus item: id derived from `n`, so `ids(_:)` recovers `n`.
  private func item(_ n: Int, _ title: String) -> SearchCorpusItem {
    let suffix = String(format: "%012d", n)
    return SearchCorpusItem(id: UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!, title: title)
  }

  private func ids(_ results: [SearchMatchDTO]) -> [Int] {
    results.compactMap { Int($0.id.uuidString.suffix(12)) }
  }

  // MARK: - Empty query

  func testEmptyQueryReturnsAllItemsWithNoRanges() async {
    let corpus = [item(1, "foo bar"), item(2, "baz")]
    for mode in Search.Mode.allCases {
      let results = await searchActor.search(query: "", within: corpus, mode: mode)
      XCTAssertEqual(ids(results), [1, 2], "mode \(mode)")
      XCTAssertTrue(results.allSatisfy { $0.score == nil && $0.ranges.isEmpty }, "mode \(mode)")
      XCTAssertEqual(results.map(\.title), ["foo bar", "baz"], "mode \(mode)")
    }
  }

  // MARK: - Exact (bug 2: Character offsets)

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

  func testExactSearchIsCaseInsensitive() async {
    let corpus = [item(1, "foo bar")]
    let results = await searchActor.search(query: "FOO", within: corpus, mode: .exact)
    XCTAssertEqual(results, [SearchMatchDTO(id: item(1, "foo bar").id, title: "foo bar", score: nil, ranges: [0..<3])])
  }

  func testExactSearchNoMatchReturnsEmpty() async {
    let corpus = [item(1, "foo bar"), item(2, "baz")]
    let results = await searchActor.search(query: "nope", within: corpus, mode: .exact)
    XCTAssertTrue(results.isEmpty)
  }

  /// Bug 2: offsets are Character (grapheme) counts, NOT UTF-16. `👍` is one
  /// grapheme / one Character but two UTF-16 code units. A correct Character
  /// offset model yields `1..<2`; a UTF-16/NSRange model would yield `1..<3`.
  func testExactOffsetsAreCharacterNotUTF16() async {
    let corpus = [item(1, "a👍b")]
    let results = await searchActor.search(query: "👍", within: corpus, mode: .exact)
    XCTAssertEqual(results, [SearchMatchDTO(id: item(1, "a👍b").id, title: "a👍b", score: nil, ranges: [1..<2])])
  }

  /// Same Character-offset guarantee via the regexp path (NSRange→Range→distance).
  func testRegexpOffsetsAreCharacterNotUTF16() async {
    let corpus = [item(1, "a👍b")]
    let results = await searchActor.search(query: "👍", within: corpus, mode: .regexp)
    XCTAssertEqual(results, [SearchMatchDTO(id: item(1, "a👍b").id, title: "a👍b", score: nil, ranges: [1..<2])])
  }

  // MARK: - Regexp (bug 5: empty match)

  func testRegexpSearchOffsets() async {
    let corpus = [item(1, "foo bar baz")]
    let ba = await searchActor.search(query: "ba", within: corpus, mode: .regexp)
    XCTAssertEqual(
      ba,
      [SearchMatchDTO(id: item(1, "foo bar baz").id, title: "foo bar baz", score: nil, ranges: [4..<6])]
    )

    let span = await searchActor.search(query: "ba.*z", within: corpus, mode: .regexp)
    XCTAssertEqual(
      span,
      [SearchMatchDTO(id: item(1, "foo bar baz").id, title: "foo bar baz", score: nil, ranges: [4..<11])]
    )
  }

  /// Bug 5: a zero-length regex match (`z*` on a string with no 'z') returns
  /// the item with a valid empty range `0..<0` (resolves to
  /// `startIndex..<startIndex` on the main actor). The item IS a match; no
  /// highlight is applied. A naive impl would drop the item, trap on
  /// `upperBound - 1`, or fail `Range(NSRange(length:0), in:)`.
  func testRegexpEmptyMatchIsZeroLengthRange() async {
    let corpus = [item(1, "abc")]
    let results = await searchActor.search(query: "z*", within: corpus, mode: .regexp)
    XCTAssertEqual(results, [SearchMatchDTO(id: item(1, "abc").id, title: "abc", score: nil, ranges: [0..<0])])
  }

  func testRegexpUnsafePatternReturnsEmpty() async {
    let corpus = [item(1, "aaaa")]
    let results = await searchActor.search(query: "(a+)+$", within: corpus, mode: .regexp)
    XCTAssertTrue(results.isEmpty)
  }

  func testRegexpInvalidPatternReturnsEmpty() async {
    let corpus = [item(1, "foo")]
    let results = await searchActor.search(query: "(", within: corpus, mode: .regexp)
    XCTAssertTrue(results.isEmpty)
  }

  // MARK: - Fuzzy

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

  func testFuzzySortsByScoreAscending() async {
    let corpus = [item(1, "axx"), item(2, "x")]
    let results = await searchActor.search(query: "x", within: corpus, mode: .fuzzy)
    XCTAssertEqual(ids(results), [2, 1]) // perfect match "x" (score 0) first
    let scores = results.compactMap { $0.score }
    XCTAssertEqual(scores.count, 2)
    XCTAssertTrue(scores[0] <= scores[1])
  }

  // MARK: - Mixed

  func testMixedSimpleTierWins() async {
    let corpus = [item(1, "foo bar"), item(2, "baz")]
    let results = await searchActor.search(query: "foo", within: corpus, mode: .mixed)
    XCTAssertEqual(results, [SearchMatchDTO(id: item(1, "foo bar").id, title: "foo bar", score: nil, ranges: [0..<3])])
  }

  func testMixedFallsThroughToRegexp() async {
    let corpus = [item(1, "foo"), item(2, "fxo"), item(3, "bar")]
    let results = await searchActor.search(query: "f.o", within: corpus, mode: .mixed)
    XCTAssertEqual(ids(results), [1, 2])
    XCTAssertTrue(results.allSatisfy { $0.ranges == [0..<3] })
  }

  func testMixedFallsThroughToFuzzy() async {
    let corpus = [item(1, "foo bar"), item(2, "xyz")]
    let results = await searchActor.search(query: "fb", within: corpus, mode: .mixed)
    XCTAssertEqual(ids(results), [1])
    XCTAssertNotNil(results.first?.score)
  }
}
