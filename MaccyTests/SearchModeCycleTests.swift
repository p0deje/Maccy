import XCTest

/// Pure unit tests for ``Search.Mode`` cycling and abbreviation glyphs.
///
/// These cover the search-field mode button's contract — declaration-order
/// cycling and one unique glyph per mode — independent of UI or main-actor
/// state (``Search.Mode`` is a `Sendable` value type with no isolation).
final class SearchModeCycleTests: XCTestCase {
  func test_next_cyclesInDeclarationOrder() {
    XCTAssertEqual(Search.Mode.exact.next, .fuzzy)
    XCTAssertEqual(Search.Mode.fuzzy.next, .regexp)
    XCTAssertEqual(Search.Mode.regexp.next, .mixed)
    XCTAssertEqual(Search.Mode.mixed.next, .exact)
  }

  func test_next_completesFullCycleWithoutRepeats() {
    var mode = Search.Mode.exact
    var visited: [Search.Mode] = []
    for _ in 0..<Search.Mode.allCases.count {
      mode = mode.next
      visited.append(mode)
    }
    // After allCases.count hops from .exact we return to .exact.
    XCTAssertEqual(mode, .exact)
    // One full cycle visits every case exactly once.
    XCTAssertEqual(Set(visited), Set(Search.Mode.allCases))
  }

  func test_abbreviation_returnsLatinGlyphPerMode() {
    XCTAssertEqual(Search.Mode.exact.abbreviation, "EX")
    XCTAssertEqual(Search.Mode.fuzzy.abbreviation, "FZ")
    XCTAssertEqual(Search.Mode.regexp.abbreviation, "RE")
    XCTAssertEqual(Search.Mode.mixed.abbreviation, "MX")
  }

  func test_abbreviation_isUniqueAcrossModes() {
    let glyphs = Search.Mode.allCases.map(\.abbreviation)
    XCTAssertEqual(glyphs.count, Set(glyphs).count, "abbreviations must be unique")
  }
}
