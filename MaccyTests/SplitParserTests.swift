import XCTest
@testable import Maccy

final class SplitParserTests: XCTestCase {
  func testElementsTrimPunctuationAndPreserveSourceRanges() {
    let line = "https://example.com/path, test@example.com。"
    let elements = SplitParser.elements(line)

    XCTAssertEqual(elements.map(\.kind), [.url, .email])
    XCTAssertEqual(elements.map(\.value), ["https://example.com/path", "test@example.com"])

    for element in elements {
      XCTAssertEqual(String(line[Range(element.range, in: line)!]), element.value)
    }
  }

  func testOverlappingMatchesPreferHigherPriorityRule() {
    let elements = SplitParser.elements("https://example.com 42")

    XCTAssertEqual(elements.first?.kind, .url)
    XCTAssertFalse(elements.contains { $0.value == "https" })
    XCTAssertTrue(elements.contains { $0.kind == .number && $0.value == "42" })
  }

  func testParseBoundsLargeSingleLineInput() {
    let result = SplitParser.parse(String(repeating: "a", count: 2_000_100))

    XCTAssertTrue(result.wasTruncated)
    XCTAssertEqual(result.lines.count, 1)
    XCTAssertEqual(result.lines[0].value.count, 2_000_000)
    XCTAssertTrue(result.lines[0].elementAnalysisSkipped)
    XCTAssertLessThanOrEqual(result.lines[0].displayValue.count, 4_001)
  }

  func testParseBoundsNumberOfLines() {
    let result = SplitParser.parse(String(repeating: "row\n", count: 600))

    XCTAssertTrue(result.wasTruncated)
    XCTAssertEqual(result.lines.count, 500)
    XCTAssertEqual(result.lines.first?.value, "row")
  }
}
