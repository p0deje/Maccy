import XCTest
@testable import Maccy

class CollectionSurroundingTests: XCTestCase {
  func testItemBeforeFirstItemReturnsNil() {
    let items = ["a", "b", "c"]

    XCTAssertNil(items.item(before: "a") { _ in true })
  }
}
