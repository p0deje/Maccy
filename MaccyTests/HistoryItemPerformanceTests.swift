import XCTest
@testable import Maccy

@MainActor
class HistoryItemPerformanceTests: XCTestCase {
  func testLargeTextSignatureSupersedesBenchmark() {
    let largeText = String(repeating: "abcdef\n", count: 20_000)
    let contents = [
      HistoryItemContent(
        type: NSPasteboard.PasteboardType.string.rawValue,
        value: largeText.data(using: .utf8)
      )
    ]
    let signature = HistoryItemEngine.signature(contents: contents, ignoringTypes: [])

    measure {
      XCTAssertTrue(HistoryItemEngine.contains(contents: contents, signature: signature))
    }
  }
}
