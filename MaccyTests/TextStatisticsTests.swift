import XCTest
@testable import Maccy

final class TextStatisticsTests: XCTestCase {
  func testEmptyString() {
    XCTAssertEqual("".textStatistics, TextStatistics(characters: 0, words: 0, lines: 0))
  }

  func testSingleLine() {
    XCTAssertEqual("Hello, world!".textStatistics, TextStatistics(characters: 13, words: 2, lines: 1))
  }

  func testMultipleLines() {
    XCTAssertEqual("foo bar\nbaz\n\nqux".textStatistics, TextStatistics(characters: 16, words: 4, lines: 4))
  }

  func testTrailingNewlineDoesNotAddLine() {
    XCTAssertEqual("foo\n".textStatistics.lines, 1)
  }

  func testCarriageReturnLineFeed() {
    XCTAssertEqual("foo\r\nbar".textStatistics, TextStatistics(characters: 7, words: 2, lines: 2))
  }

  func testWhitespaceOnly() {
    XCTAssertEqual(" \t ".textStatistics.words, 0)
  }

  func testPunctuationIsNotAWord() {
    XCTAssertEqual("don't stop - e.g. 3.14".textStatistics.words, 4)
  }

  func testCharactersAreGraphemeClusters() {
    XCTAssertEqual("👍🏽👨‍👩‍👧é".textStatistics.characters, 3)
  }

  func testWordsWithoutSpaces() {
    XCTAssertGreaterThan("你好世界".textStatistics.words, 1)
  }
}
