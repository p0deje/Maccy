import AppKit
import Foundation
import XCTest
@testable import Maccy

// Behavior tests for the `ImageProcessor` actor — the production
// `ImageProcessing` conformance that backs thumbnails with `ThumbnailCache`
// (memory + disk) and builds previews transiently via `ImageDownsampler`.
//
// `@MainActor` because `FixtureLoader.imageData` uses AppKit (`NSImage`
// TIFF representation). Each test injects a unique temp directory so it never
// touches the runner's real Application Support, mirroring `ThumbnailCacheTests`.
@MainActor
final class ImageProcessorTests: XCTestCase {
  /// Builds a processor backed by a fresh temp-disk cache, returning the processor and its cache directory.
  private func makeProcessor() -> (ImageProcessor, URL) {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "ImageProcessorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let processor = ImageProcessor(cache: ThumbnailCache(diskDirectory: dir))
    return (processor, dir)
  }

  /// A cache-backed thumbnail is downsampled so its longest side is within the requested maximum.
  func testThumbnailReturnsImageWithinMax() async throws {
    let (processor, _) = makeProcessor()
    let data = try FixtureLoader.imageData()

    let thumbnail = await processor.thumbnail(for: data, max: NSSize(width: 100, height: 100))

    XCTAssertNotNil(thumbnail)
    XCTAssertLessThanOrEqual(thumbnail?.size.width ?? .infinity, 100)
  }

  /// A transient preview (no cache) is still downsampled to the requested longest side.
  func testPreviewReturnsImageWithinMax() async throws {
    let (processor, _) = makeProcessor()
    let data = try FixtureLoader.imageData()

    let preview = await processor.preview(for: data, max: NSSize(width: 80, height: 80))

    XCTAssertNotNil(preview)
    XCTAssertLessThanOrEqual(preview?.size.width ?? .infinity, 80)
  }

  /// Corrupt image data must surface `nil`, not crash or log an ImageIO error.
  ///
  /// The byte-count guard in `ImageDownsampler` keeps ImageIO from logging on this input; the actor must propagate `nil`.
  func testThumbnailOfCorruptDataReturnsNil() async throws {
    let (processor, _) = makeProcessor()
    let corrupt = Data([0, 1, 2, 3])

    let thumbnail = await processor.thumbnail(for: corrupt, max: NSSize(width: 50, height: 50))

    XCTAssertNil(thumbnail)
  }
}
