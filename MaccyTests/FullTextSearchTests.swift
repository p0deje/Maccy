import XCTest

@testable import Maccy

/// Tests full-text exact and regexp matching over an item's body (the capped
/// scan window carried on `SearchCorpusItem.body`), independent of the title.
///
/// The title is matched first; when it does not contain the query, the body is
/// scanned so a clip still surfaces via its content. A body match carries
/// `inBody: true` with offsets that index into the body, not the title.
final class FullTextSearchTests: XCTestCase {
  private let searchActor = SearchActor()

  /// A needle deep in the body — well past any title window — is found by exact
  /// search, reported as a body match with body-relative offsets.
  func testExactFindsDeepBodyMatch() async {
    let body = String(repeating: "a", count: 5_000) + "NEEDLE" + String(repeating: "b", count: 1_000)
    let corpus = [SearchCorpusItem(id: UUID(), title: "short title", body: body)]

    let results = await searchActor.search(query: "NEEDLE", within: corpus, mode: .exact)

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.inBody, true)
    XCTAssertEqual(results.first?.ranges, [5_000..<5_006])
  }

  /// A needle deep in the body is found by regexp search, reported as a body match.
  func testRegexpFindsDeepBodyMatch() async {
    let body = String(repeating: "x", count: 10_000) + "token123" + String(repeating: "y", count: 500)
    let corpus = [SearchCorpusItem(id: UUID(), title: "title", body: body)]

    let results = await searchActor.search(query: "token[0-9]+", within: corpus, mode: .regexp)

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.inBody, true)
    XCTAssertEqual(results.first?.ranges, [10_000..<10_008])
  }

  /// A query absent from both title and body matches nothing.
  func testQueryInNeitherTitleNorBody() async {
    let corpus = [SearchCorpusItem(id: UUID(), title: "hello", body: "world")]

    let exact = await searchActor.search(query: "missing", within: corpus, mode: .exact)
    let regexp = await searchActor.search(query: "missing", within: corpus, mode: .regexp)

    XCTAssertTrue(exact.isEmpty)
    XCTAssertTrue(regexp.isEmpty)
  }

  /// When the query matches both the title and the body, the title match wins:
  /// offsets index into the title and `inBody` is false (the title is what the
  /// row displays, so highlighting it is the useful outcome).
  func testTitleMatchPreferredOverBodyMatch() async {
    let corpus = [SearchCorpusItem(id: UUID(), title: "NEEDLE title", body: "NEEDLE body")]

    let results = await searchActor.search(query: "NEEDLE", within: corpus, mode: .exact)

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.inBody, false)
    XCTAssertEqual(results.first?.ranges, [0..<6])
  }

  /// The actor searches only the body it is given (the body is capped upstream
  /// at `TextLimits.searchBody` when the corpus is built); a needle beyond that
  /// window is absent from the body and not found.
  func testNeedleBeyondBodyWindowNotFound() async {
    let full = String(repeating: "a", count: TextLimits.searchBody) + "NEEDLE"
    let cappedBody = String(full.prefix(TextLimits.searchBody))
    let corpus = [SearchCorpusItem(id: UUID(), title: "x", body: cappedBody)]

    let results = await searchActor.search(query: "NEEDLE", within: corpus, mode: .exact)

    XCTAssertTrue(results.isEmpty)
  }
}
