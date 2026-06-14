import XCTest
@testable import Maccy

@MainActor
class StorageBackgroundContextTests: XCTestCase {
  func testNewBackgroundContextCreatesSeparateContextWithoutUndo() {
    let backgroundContext = Storage.shared.newBackgroundContext()

    XCTAssertTrue(backgroundContext !== Storage.shared.context)
    XCTAssertNil(backgroundContext.undoManager)
  }
}
