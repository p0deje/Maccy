import XCTest

@testable import Maccy

/// Tests fuzzy matching over an item's body — the title-first / body-on-miss
/// path that mirrors the exact and regexp full-text tiers.
///
/// The title is matched first; when the title does not fuzzy-match, the body
/// prefix (capped at `TextLimits.fuzzy`) is scanned so a clip still surfaces via
/// its content. A body match carries `inBody: true` with offsets that index into
/// the body. Across the result list, title matches rank before body matches —
/// Fuse scores are not normalized across haystack length, so mixing a title
/// score against a body score would order arbitrarily.
final class FullTextFuzzyTests: XCTestCase {
  private let searchActor = SearchActor()

  /// Builds a deterministic corpus item whose id encodes `number`, so `ids(_:)`
  /// can recover the original integer from the returned matches.
  private func item(_ number: Int, title: String, body: String = "") -> SearchCorpusItem {
    let suffix = String(format: "%012d", number)
    return SearchCorpusItem(id: UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!, title: title, body: body)
  }

  /// Extracts the trailing integer each result id encodes, in match order.
  private func ids(_ results: [SearchMatchDTO]) -> [Int] {
    results.compactMap { Int($0.id.uuidString.suffix(12)) }
  }

  /// A query that fuzzy-matches the body but not the title surfaces the item as
  /// a body match: `inBody` is true and the ranges index into the body.
  func testFuzzyFindsBodyMatchAsInBody() async {
    let corpus = [item(1, title: "zzz", body: "hello world")]

    let results = await searchActor.search(query: "hw", within: corpus, mode: .fuzzy)

    XCTAssertEqual(ids(results), [1])
    XCTAssertEqual(results.first?.inBody, true)
    let bodyCount = "hello world".count
    XCTAssertTrue(
      results.first?.ranges.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= bodyCount && $0.lowerBound <= $0.upperBound } ?? false
    )
  }

  /// When the query fuzzy-matches both the title and the body, the title match
  /// wins: `inBody` is false and the ranges index into the title (the row
  /// displays the title, so highlighting it is the useful outcome).
  func testFuzzyPrefersTitleMatchOverBodyMatch() async {
    let corpus = [item(1, title: "foo bar", body: "foo bar")]

    let results = await searchActor.search(query: "fb", within: corpus, mode: .fuzzy)

    XCTAssertEqual(ids(results), [1])
    XCTAssertEqual(results.first?.inBody, false)
    let titleCount = "foo bar".count
    XCTAssertTrue(
      results.first?.ranges.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= titleCount && $0.lowerBound <= $0.upperBound } ?? false
    )
  }

  /// An item whose title and body both fail to fuzzy-match is not returned.
  func testFuzzyMissesBothTitleAndBody() async {
    let corpus = [item(1, title: "abc", body: "def")]

    let results = await searchActor.search(query: "xyz", within: corpus, mode: .fuzzy)

    XCTAssertTrue(results.isEmpty)
  }

  /// An empty body (an image clip, or an old row with no searchable text)
  /// degrades to title-only fuzzy: a title match still surfaces, but there is no
  /// body fallback.
  func testFuzzyEmptyBodyDegradesToTitleOnly() async {
    let matching = [item(1, title: "foo bar", body: "")]
    let nonMatching = [item(2, title: "zzz", body: "")]

    let hit = await searchActor.search(query: "fb", within: matching, mode: .fuzzy)
    let miss = await searchActor.search(query: "fb", within: nonMatching, mode: .fuzzy)

    XCTAssertEqual(ids(hit), [1])
    XCTAssertTrue(miss.isEmpty)
  }

  /// A body match within the fuzzy prefix window is found.
  func testFuzzyFindsBodyMatchWithinPrefix() async {
    let body = "needle" + String(repeating: "x", count: TextLimits.fuzzy)
    let corpus = [item(1, title: "zzz", body: body)]

    let results = await searchActor.search(query: "ndl", within: corpus, mode: .fuzzy)

    XCTAssertEqual(ids(results), [1])
    XCTAssertEqual(results.first?.inBody, true)
  }

  /// A body match beyond the fuzzy prefix window (`TextLimits.fuzzy` graphemes)
  /// is not found: the prefix is scanned, the tail is not. Exact and regexp
  /// still scan the full body, so a deep match is not lost silently — it just
  /// does not surface via fuzzy.
  func testFuzzyBodyMatchBeyondPrefixNotFound() async {
    let body = String(repeating: "x", count: TextLimits.fuzzy + 1) + "needle"
    let corpus = [item(1, title: "zzz", body: body)]

    let results = await searchActor.search(query: "ndl", within: corpus, mode: .fuzzy)

    XCTAssertTrue(results.isEmpty)
  }

  /// Title matches rank before body matches across the result list, even when a
  /// body match has a better (lower) Fuse score. A pure cross-field score sort
  /// would place the perfect body match first; the title-preferred order keeps
  /// title hits above content-only hits (Fuse scores are not normalized across
  /// haystack length, so a title score and a body score are not comparable).
  func testFuzzyRanksTitleBucketBeforeBodyBucket() async {
    // Item 1 matches only in the title ("foo bar" ~ "fb", imperfect).
    // Item 2 matches only in the body ("fb" == "fb", perfect, score 0).
    let corpus = [item(1, title: "foo bar", body: ""), item(2, title: "zzz", body: "fb")]

    let results = await searchActor.search(query: "fb", within: corpus, mode: .fuzzy)

    XCTAssertEqual(ids(results), [1, 2])
    XCTAssertEqual(results.map(\.inBody), [false, true])
  }

  /// Body match offsets are grapheme (Character) counts, not UTF-16 code units.
  /// `👍` is one grapheme but two UTF-16 units, so a body match landing on it
  /// yields a grapheme-relative range.
  func testFuzzyBodyOffsetsAreCharacterNotUTF16() async {
    let corpus = [item(1, title: "zzz", body: "a👍b")]

    let results = await searchActor.search(query: "👍", within: corpus, mode: .fuzzy)

    XCTAssertEqual(ids(results), [1])
    XCTAssertEqual(results.first?.inBody, true)
    XCTAssertEqual(results.first?.ranges, [1..<2])
  }
}
