import Testing
@testable import Maccy

@MainActor
struct CollectionSurroundingTests {
  let items = ["pin1", "pin2", "recent1", "recent2", "recent3"]

  @Test("Nearest item other than itself", arguments: [
    ("recent1", "recent2"),
    ("recent2", "recent3"),
    ("recent3", "recent2")
  ])
  func nearestItemOtherThanItself(current: String, expected: String) {
    #expect(items.nearest(to: current) { $0 != current } == expected)
  }

  @Test("Nearest is nil when nothing matches")
  func nearestIsNilWhenNothingMatches() {
    #expect(items.nearest(to: "recent1") { _ in false } == nil)
  }

  @Test("Nearest is nil for a missing item")
  func nearestIsNilForMissingItem() {
    #expect(items.nearest(to: "missing") { _ in true } == nil)
  }

  @Test("Nearest skips multiple excluded leading items")
  func testNearestWithMultipleLeadingMatchesExcluded() {
    let excluded: Set<String> = ["a", "b", "recent1"]
    let items = ["a", "b", "recent1", "recent2", "recent3"]
    #expect(items.nearest(to: "recent1") { !excluded.contains($0) } == "recent2")
  }
}
