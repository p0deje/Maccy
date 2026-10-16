import Testing
@testable import Maccy

@MainActor
struct ShortenedTests {
  @Test("Shortened returns at most max length")
  func shortenedReturnsAtMostMaxLength() {
    #expect("abcdef".shortened(to: 3) == "abc")
  }

  @Test("Shortened is a no-op within the limit", arguments: ["abc", ""])
  func shortenedNoOpWhenWithinLimit(input: String) {
    #expect(input.shortened(to: 3) == input)
  }

  @Test("Shortened with a large cap is a no-op")
  func shortenedLargeCapIsNoOp() {
    #expect("abcdefghij".shortened(to: 1_000) == "abcdefghij")
  }

  @Test("Shortened result never exceeds max length", arguments: 0...8)
  func shortenedResultNeverExceedsMaxLength(length: Int) {
    let input = "abcdef"
    let result = input.shortened(to: length)
    #expect(result.count <= length)
    #expect(result.count == min(length, input.count))
  }
}
