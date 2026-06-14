import XCTest
@testable import Maccy

class HistoryItemFileDataTests: XCTestCase {
  func testImageFromUniversalClipboardDoesNotReadFileWhenSizeCheckFails() {
    let data = HistoryItem.dataFromFileIfAllowed(
      URL(fileURLWithPath: "/tmp/missing.jpeg"),
      resourceValues: { _ in throw CocoaError(.fileReadNoSuchFile) },
      dataContents: { _ in
        XCTFail("File data should not be read when size metadata cannot be loaded.")
        return Data("unexpected".utf8)
      },
      logErrors: false
    )

    XCTAssertNil(data)
  }
}
