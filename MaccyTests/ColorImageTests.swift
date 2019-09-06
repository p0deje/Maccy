import XCTest
@testable import Maccy

class ColorImageTests: XCTestCase {
  func testColorImageFromShortHex() {
    XCTAssertNotNil(ColorImage.from("fff"))
  }

  func testColorFromFullHex() {
    XCTAssertNotNil(ColorImage.from("#ff8942"))
  }

  func testColorFromNotHex() {
    XCTAssertNil(ColorImage.from("foo"))
  }
}
