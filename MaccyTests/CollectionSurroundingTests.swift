import XCTest
@testable import Maccy

class CollectionSurroundingTests: XCTestCase {
  let items = ["pin1", "pin2", "recent1", "recent2", "recent3"]

  func testNearest() {
    XCTAssertEqual(items.nearest(to: "recent1") { $0 != "recent1" }, "recent2")
    XCTAssertEqual(items.nearest(to: "recent2") { $0 != "recent2" }, "recent3")
    XCTAssertEqual(items.nearest(to: "recent3") { $0 != "recent3" }, "recent2")
    XCTAssertNil(items.nearest(to: "recent1") { _ in false })
    XCTAssertNil(items.nearest(to: "missing") { _ in true })
  }

  func testNearestWithMultipleLeadingMatchesExcluded() {
    let excluded: Set<String> = ["a", "b", "recent1"]
    let items = ["a", "b", "recent1", "recent2", "recent3"]
    XCTAssertEqual(items.nearest(to: "recent1") { !excluded.contains($0) }, "recent2")
  }
}
