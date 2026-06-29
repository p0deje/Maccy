import XCTest
@testable import Maccy

/// Tests for `ColorImage` hex-color parsing.
@MainActor
class ColorImageTests: XCTestCase {
  /// A short 3-digit hex string produces a color image.
  func testColorImageFromShortHex() {
    XCTAssertNotNil(ColorImage.from("fff"))
  }

  /// A full 6-digit hex string (with or without `#`) produces a color image.
  func testColorFromFullHex() {
    XCTAssertNotNil(ColorImage.from("#ff8942"))
  }

  /// A non-hex string produces no color image.
  func testColorFromNotHex() {
    XCTAssertNil(ColorImage.from("foo"))
  }
}
