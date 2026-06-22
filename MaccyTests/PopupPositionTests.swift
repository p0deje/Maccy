import AppKit
import XCTest
@testable import Maccy

class PopupPositionTests: XCTestCase {
  func testCursorOriginFitsBottomOfVisibleFrame() {
    let visibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
    let origin = PopupPosition.cursorOrigin(
      size: NSSize(width: 420, height: 500),
      mouseLocation: NSPoint(x: 500, y: 30),
      visibleFrame: visibleFrame
    )

    XCTAssertEqual(origin.x, 500)
    XCTAssertEqual(origin.y, visibleFrame.minY)
  }

  func testCursorOriginStaysInsideCursorScreenAtEdge() {
    let visibleFrame = NSRect(x: -1440, y: 0, width: 1440, height: 900)
    let size = NSSize(width: 600, height: 400)
    let origin = PopupPosition.cursorOrigin(
      size: size,
      mouseLocation: NSPoint(x: -20, y: 500),
      visibleFrame: visibleFrame
    )

    XCTAssertEqual(origin.x, -600)
    XCTAssertEqual(origin.y, 100)
    XCTAssertGreaterThanOrEqual(origin.x, visibleFrame.minX)
    XCTAssertLessThanOrEqual(origin.x + size.width, visibleFrame.maxX)
  }

  func testConstrainedSizeDoesNotExceedVisibleFrame() {
    let size = PopupPosition.constrainedSize(
      NSSize(width: 1200, height: 900),
      visibleFrame: NSRect(x: 0, y: 0, width: 800, height: 600)
    )

    XCTAssertEqual(size.width, 800)
    XCTAssertEqual(size.height, 600)
  }
}
