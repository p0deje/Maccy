import XCTest
@testable import Maccy

final class UnsafeForTitleLayoutTests: XCTestCase {
  private let objectReplacement = "\u{FFFC}"

  func testRemovesLeadingOccurrence() {
    XCTAssertEqual((objectReplacement + "foo").removingScalarsUnsafeForTitleLayout(), "foo")
  }

  func testRemovesTrailingOccurrence() {
    XCTAssertEqual(("foo" + objectReplacement).removingScalarsUnsafeForTitleLayout(), "foo")
  }

  func testRemovesInteriorOccurrence() {
    XCTAssertEqual(("a" + objectReplacement + "b").removingScalarsUnsafeForTitleLayout(), "ab")
  }

  func testRemovesEveryOccurrence() {
    let input = objectReplacement + "复制" + objectReplacement + "粘贴" + objectReplacement
    XCTAssertEqual(input.removingScalarsUnsafeForTitleLayout(), "复制粘贴")
  }

  func testAllUnsafeBecomesEmpty() {
    let input = String(repeating: objectReplacement, count: 3)
    XCTAssertEqual(input.removingScalarsUnsafeForTitleLayout(), "")
  }

  // U+FFFC followed by a combining mark is a single Character, so filtering by
  // Character would leave the unsafe scalar in place and the hang would survive.
  func testRemovesOccurrenceInsideGraphemeCluster() {
    let input = objectReplacement + "\u{0301}" + "复制"
    let result = input.removingScalarsUnsafeForTitleLayout()
    XCTAssertFalse(result.unicodeScalars.contains { $0.value == 0xFFFC })
    XCTAssertEqual(result, "\u{0301}复制")
  }

  func testKeepsSafeStringsUntouched() {
    XCTAssertEqual("foo bar".removingScalarsUnsafeForTitleLayout(), "foo bar")
    XCTAssertEqual("复制粘贴测试".removingScalarsUnsafeForTitleLayout(), "复制粘贴测试")
    XCTAssertEqual("".removingScalarsUnsafeForTitleLayout(), "")
  }

  // Only U+FFFC is known to trigger the hang, so nothing else may be dropped.
  func testKeepsOtherInvisibleAndReplacementScalars() {
    XCTAssertEqual("\u{FFFD}foo".removingScalarsUnsafeForTitleLayout(), "\u{FFFD}foo")
    XCTAssertEqual("\u{200B}foo".removingScalarsUnsafeForTitleLayout(), "\u{200B}foo")
    XCTAssertEqual("\u{FEFF}foo".removingScalarsUnsafeForTitleLayout(), "\u{FEFF}foo")
  }

  func testKeepsSpecialSymbolsUsedByTitles() {
    XCTAssertEqual("⏎foo⇥bar·".removingScalarsUnsafeForTitleLayout(), "⏎foo⇥bar·")
  }

  func testKeepsMultiScalarGraphemeClusters() {
    XCTAssertEqual("🇨🇳".removingScalarsUnsafeForTitleLayout(), "🇨🇳")
    XCTAssertEqual("🚀foo".removingScalarsUnsafeForTitleLayout(), "🚀foo")
    XCTAssertEqual("e\u{0301}".removingScalarsUnsafeForTitleLayout(), "e\u{0301}")
  }

  func testDetectsUnsafeScalars() {
    XCTAssertTrue((objectReplacement + "foo").containsScalarsUnsafeForTitleLayout)
    XCTAssertTrue((objectReplacement + "\u{0301}foo").containsScalarsUnsafeForTitleLayout)
    XCTAssertFalse("foo".containsScalarsUnsafeForTitleLayout)
    XCTAssertFalse("".containsScalarsUnsafeForTitleLayout)
    XCTAssertFalse("\u{FFFD}foo".containsScalarsUnsafeForTitleLayout)
  }
}
