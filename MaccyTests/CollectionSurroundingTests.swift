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

@MainActor
struct ConcatenatedCollectionTests {
  @Test("Leading slice keeps its nonzero start index")
  func leadingSlice() {
    let items = ConcatenatedCollection([10, 20, 30][1...], [40])
    #expect(items[1] == 30)
    #expect(Array(items) == [20, 30, 40])
  }

  @Test("Trailing slice keeps its nonzero start index")
  func trailingSlice() {
    let items = ConcatenatedCollection([10], [20, 30, 40][1...])
    #expect(items[2] == 40)
    #expect(Array(items) == [10, 30, 40])
  }

  @Test("Empty segments and nested slices preserve order")
  func emptyAndNestedSegments() {
    #expect(Array(ConcatenatedCollection([Int](), [10, 20][1...])) == [20])
    #expect(Array(ConcatenatedCollection([10, 20][1...], [Int]())) == [20])
    let items = ConcatenatedCollection([10, 20][1...], ConcatenatedCollection([30], [40, 50][1...]))
    #expect(Array(items) == [20, 30, 50])
    #expect(Array(items.reversed()) == [50, 30, 20])
  }
}
