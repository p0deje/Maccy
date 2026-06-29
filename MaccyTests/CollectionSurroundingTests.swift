import XCTest
@testable import Maccy

/// Tests for the `Collection` surrounding-item helpers.
class CollectionSurroundingTests: XCTestCase {
  /// `item(before:)` returns nil when the candidate is the first element.
  func testItemBeforeFirstItemReturnsNil() {
    let items = ["a", "b", "c"]

    XCTAssertNil(items.item(before: "a") { _ in true })
  }
}
