import XCTest
@testable import Maccy

/// Tests for `HistoryItem.dataFromFileIfAllowed` and its size-guard behavior.
class HistoryItemFileDataTests: XCTestCase {
  /// When a file's size metadata can't be loaded, the file data is never read.
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
