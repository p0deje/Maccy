import XCTest
@testable import Maccy

/// Contract tests for the `PassthroughImageProcessor` test double — the conformance that wraps the legacy `NSImage(data:)` resize path.
class ImageProcessingContractTests: XCTestCase {
  /// A passthrough thumbnail is downsampled to fit the requested maximum, preserving aspect ratio.
  func testPassthroughThumbnailUsesExistingResizePath() async throws {
    let data = try imageData(size: NSSize(width: 80, height: 40))
    let processor = PassthroughImageProcessor()

    let thumbnail = await processor.thumbnail(for: data, max: CGSize(width: 40, height: 40))

    XCTAssertEqual(thumbnail?.size, NSSize(width: 40, height: 20))
  }

  /// A passthrough preview never upscales an image smaller than the maximum.
  func testPassthroughPreviewDoesNotUpscale() async throws {
    let data = try imageData(size: NSSize(width: 20, height: 20))
    let processor = PassthroughImageProcessor()

    let preview = await processor.preview(for: data, max: CGSize(width: 40, height: 40))

    XCTAssertEqual(preview?.size, NSSize(width: 20, height: 20))
  }

  /// Invalid image data yields `nil`.
  func testPassthroughReturnsNilForInvalidImageData() async {
    let processor = PassthroughImageProcessor()

    let thumbnail = await processor.thumbnail(for: Data("not an image".utf8), max: CGSize(width: 40, height: 40))

    XCTAssertNil(thumbnail)
  }

  /// Builds a flat-red image of the given size and returns its TIFF representation.
  private func imageData(size: NSSize) throws -> Data {
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()

    return try XCTUnwrap(image.tiffRepresentation)
  }
}
