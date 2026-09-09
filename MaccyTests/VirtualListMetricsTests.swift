import XCTest
@testable import Maccy

class VirtualListMetricsTests: XCTestCase {
  private func metrics(count: Int, tall: [Int] = []) -> VirtualListMetrics {
    VirtualListMetrics(rowHeight: 10, tallRowHeight: 30, totalCount: count, tallRowIndices: tall)
  }

  func testUniformHeights() {
    let uniform = metrics(count: 100)

    XCTAssertEqual(uniform.totalHeight, 1000)
    XCTAssertEqual(uniform.offset(ofRow: 0), 0)
    XCTAssertEqual(uniform.offset(ofRow: 50), 500)
    XCTAssertEqual(uniform.height(ofRow: 50), 10)
    XCTAssertEqual(uniform.row(atOffset: 505), 50)
    XCTAssertEqual(uniform.row(atOffset: 0), 0)
  }

  func testTallRowsAffectTotalHeight() {
    // Rows 2 and 5 are tall: 6 * 10 + 2 * 30 = 120.
    XCTAssertEqual(metrics(count: 8, tall: [2, 5]).totalHeight, 120)
  }

  func testOffsetsAccountForTallRows() {
    let mixed = metrics(count: 8, tall: [2, 5])

    XCTAssertEqual(mixed.offset(ofRow: 1), 10)
    XCTAssertEqual(mixed.offset(ofRow: 2), 20)
    XCTAssertEqual(mixed.offset(ofRow: 3), 50)
    XCTAssertEqual(mixed.offset(ofRow: 5), 70)
    XCTAssertEqual(mixed.offset(ofRow: 6), 100)
    XCTAssertEqual(mixed.height(ofRow: 2), 30)
    XCTAssertEqual(mixed.height(ofRow: 3), 10)
  }

  func testRowAtOffsetWithTallRows() {
    let mixed = metrics(count: 8, tall: [2, 5])

    // Row 2 spans 20..<50, row 3 starts at 50.
    XCTAssertEqual(mixed.row(atOffset: 49.9), 2)
    XCTAssertEqual(mixed.row(atOffset: 50), 3)
    // Offsets past the end clamp to the last row.
    XCTAssertEqual(mixed.row(atOffset: 10_000), 7)
  }

  func testRowsInViewport() {
    let mixed = metrics(count: 8, tall: [2, 5])

    // 15 is inside row 1, 65 is inside row 4 (60..<70).
    XCTAssertEqual(mixed.rows(in: 15...65), 1..<5)
    XCTAssertEqual(mixed.rows(in: 0...119), 0..<8)
  }

  func testEmptyList() {
    let empty = metrics(count: 0)

    XCTAssertEqual(empty.totalHeight, 0)
    XCTAssertEqual(empty.rows(in: 0...100), 0..<0)
  }

  func testTallIndicesBeyondCountAreIgnoredInTotalHeight() {
    // Stale indices past the end must not inflate the height.
    XCTAssertEqual(metrics(count: 2, tall: [0, 5, 9]).totalHeight, 40)
  }
}
