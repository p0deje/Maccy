import XCTest
@testable import Maccy

class PopupPositionTests: XCTestCase {
  let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
  let size = NSSize(width: 300, height: 400)

  func testClampNoAdjustmentNeeded() {
    let origin = NSPoint(x: 100, y: 200)
    let result = PopupPosition.clamp(origin, size, to: screen)
    XCTAssertEqual(result.x, 100)
    XCTAssertEqual(result.y, 200)
  }

  func testClampBottomEdge() {
    let origin = NSPoint(x: 100, y: -200)
    let result = PopupPosition.clamp(origin, size, to: screen)
    XCTAssertEqual(result.x, 100)
    XCTAssertEqual(result.y, 0)
  }

  func testClampTopEdge() {
    // origin.y + height = 800 + 400 = 1200 > 900
    let origin = NSPoint(x: 100, y: 800)
    let result = PopupPosition.clamp(origin, size, to: screen)
    XCTAssertEqual(result.x, 100)
    XCTAssertEqual(result.y, 500) // 900 - 400
  }

  func testClampRightEdge() {
    // origin.x + width = 1300 + 300 = 1600 > 1440
    let origin = NSPoint(x: 1300, y: 200)
    let result = PopupPosition.clamp(origin, size, to: screen)
    XCTAssertEqual(result.x, 1140) // 1440 - 300
    XCTAssertEqual(result.y, 200)
  }

  func testClampLeftEdge() {
    let origin = NSPoint(x: -50, y: 200)
    let result = PopupPosition.clamp(origin, size, to: screen)
    XCTAssertEqual(result.x, 0)
    XCTAssertEqual(result.y, 200)
  }

  func testClampBottomAndRightCorner() {
    let origin = NSPoint(x: 1300, y: -100)
    let result = PopupPosition.clamp(origin, size, to: screen)
    XCTAssertEqual(result.x, 1140) // 1440 - 300
    XCTAssertEqual(result.y, 0)
  }

  func testClampWithNonZeroScreenOrigin() {
    // Secondary monitor starting at x=1440
    let secondScreen = NSRect(x: 1440, y: 0, width: 1440, height: 900)
    let origin = NSPoint(x: 1430, y: 200)
    let result = PopupPosition.clamp(origin, size, to: secondScreen)
    XCTAssertEqual(result.x, 1440) // clamped to secondScreen.minX
    XCTAssertEqual(result.y, 200)
  }

  func testClampExactlyOnEdge() {
    // Right edge: 1140 + 300 = 1440 == screen.maxX — no adjustment needed
    let origin = NSPoint(x: 1140, y: 200)
    let result = PopupPosition.clamp(origin, size, to: screen)
    XCTAssertEqual(result.x, 1140)
    XCTAssertEqual(result.y, 200)
  }

  func testClampPopupLargerThanScreen() {
    // Popup larger than screen: bottom-left priority
    let largeSize = NSSize(width: 2000, height: 1200)
    let origin = NSPoint(x: 100, y: 100)
    let result = PopupPosition.clamp(origin, largeSize, to: screen)
    XCTAssertEqual(result.x, 0) // left edge wins
    XCTAssertEqual(result.y, 0) // bottom edge wins
  }
}
