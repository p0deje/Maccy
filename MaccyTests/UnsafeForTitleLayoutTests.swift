import Testing
@testable import Maccy

private let objectReplacement = "\u{FFFC}"

private let removalCases: [(input: String, expected: String)] = [
  (objectReplacement + "foo", "foo"),
  ("foo" + objectReplacement, "foo"),
  ("a" + objectReplacement + "b", "ab"),
  (objectReplacement + "复制" + objectReplacement + "粘贴" + objectReplacement, "复制粘贴"),
  (String(repeating: objectReplacement, count: 3), "")
]

@MainActor
struct UnsafeForTitleLayoutTests {
  @Test("Removes U+FFFC", arguments: removalCases)
  func removesObjectReplacement(input: String, expected: String) {
    #expect(input.removingScalarsUnsafeForTitleLayout() == expected)
  }

  // U+FFFC followed by a combining mark is a single Character, so filtering by
  // Character would leave the unsafe scalar in place and the hang would survive.
  @Test("Removes U+FFFC inside a grapheme cluster")
  func removesOccurrenceInsideGraphemeCluster() {
    let input = objectReplacement + "\u{0301}" + "复制"
    let result = input.removingScalarsUnsafeForTitleLayout()
    #expect(!result.unicodeScalars.contains { $0.value == 0xFFFC })
    #expect(result == "\u{0301}复制")
  }

  @Test("Keeps safe strings untouched", arguments: ["foo bar", "复制粘贴测试", ""])
  func keepsSafeStringsUntouched(input: String) {
    #expect(input.removingScalarsUnsafeForTitleLayout() == input)
  }

  // Only U+FFFC is known to trigger the hang, so nothing else may be dropped.
  @Test("Keeps other invisible and replacement scalars", arguments: ["\u{FFFD}foo", "\u{200B}foo", "\u{FEFF}foo"])
  func keepsOtherInvisibleAndReplacementScalars(input: String) {
    #expect(input.removingScalarsUnsafeForTitleLayout() == input)
  }

  @Test("Keeps special symbols used by titles")
  func keepsSpecialSymbolsUsedByTitles() {
    #expect("⏎foo⇥bar·".removingScalarsUnsafeForTitleLayout() == "⏎foo⇥bar·")
  }

  @Test("Keeps multi-scalar grapheme clusters", arguments: ["🇨🇳", "🚀foo", "e\u{0301}"])
  func keepsMultiScalarGraphemeClusters(input: String) {
    #expect(input.removingScalarsUnsafeForTitleLayout() == input)
  }

  @Test("Detects unsafe scalars", arguments: [objectReplacement + "foo", objectReplacement + "\u{0301}foo"])
  func detectsUnsafeScalars(input: String) {
    #expect(input.containsScalarsUnsafeForTitleLayout)
  }

  @Test("Does not flag safe strings", arguments: ["foo", "", "\u{FFFD}foo"])
  func doesNotFlagSafeStrings(input: String) {
    #expect(!input.containsScalarsUnsafeForTitleLayout)
  }
}
