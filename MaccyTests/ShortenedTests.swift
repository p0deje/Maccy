import XCTest
@testable import Maccy

final class ShortenedTests: XCTestCase {
  func testShortenedReturnsAtMostMaxLength() {
    XCTAssertEqual("abcdef".shortened(to: 3), "abc")
  }

  func testShortenedNoOpWhenWithinLimit() {
    XCTAssertEqual("abc".shortened(to: 3), "abc")
    XCTAssertEqual("".shortened(to: 3), "")
  }

  func testShortenedLargeCapIsNoOp() {
    XCTAssertEqual("abcdefghij".shortened(to: 1_000), "abcdefghij")
  }

  func testShortenedResultNeverExceedsMaxLength() {
    let input = "abcdef"
    for length in 0...8 {
      let result = input.shortened(to: length)
      XCTAssertLessThanOrEqual(result.count, length, "shortened(to: \(length)) must be <= \(length) chars")
      XCTAssertEqual(result.count, min(length, input.count))
    }
  }
}
