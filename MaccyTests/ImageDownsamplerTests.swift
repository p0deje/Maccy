import AppKit
import CoreGraphics
import Foundation
import XCTest

@MainActor
final class ImageDownsamplerTests: XCTestCase {
  func testThumbnailStaysWithinMaxAndPreservesAspectRatio() throws {
    let data = try FixtureLoader.imageData(size: NSSize(width: 400, height: 300))

    let thumbnail = ImageDownsampler.thumbnail(data: data, max: 100)

    let image = try XCTUnwrap(thumbnail)
    XCTAssertLessThanOrEqual(image.width, 100)
    XCTAssertLessThanOrEqual(image.height, 100)
    // Aspect ratio (4:3) should be preserved: longest side scaled to 100.
    XCTAssertEqual(Double(image.width) / Double(image.height), 4.0 / 3.0, accuracy: 0.05)
  }

  func testThumbnailOfCorruptDataReturnsNil() {
    let corrupt = Data([0x00, 0x01, 0x02, 0x03])

    let thumbnail = ImageDownsampler.thumbnail(data: corrupt, max: 100)

    XCTAssertNil(thumbnail)
  }

  func testThumbnailOfEmptyDataReturnsNil() {
    let empty = Data()

    let thumbnail = ImageDownsampler.thumbnail(data: empty, max: 100)

    XCTAssertNil(thumbnail)
  }
}
