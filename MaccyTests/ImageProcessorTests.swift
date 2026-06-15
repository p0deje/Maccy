import AppKit
import Foundation
import XCTest
@testable import Maccy

// Behavior tests for the BS-3.3 `ImageProcessor` actor — the production
// `ImageProcessing` conformance that backs thumbnails with `ThumbnailCache`
// (memory + disk) and builds previews transiently via `ImageDownsampler`.
//
// `@MainActor` because `FixtureLoader.imageData` uses AppKit (`NSImage`
// TIFF representation). Each test injects a unique temp directory so it never
// touches the runner's real Application Support, mirroring `ThumbnailCacheTests`.
@MainActor
final class ImageProcessorTests: XCTestCase {
  private func makeProcessor() -> (ImageProcessor, URL) {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "ImageProcessorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let processor = ImageProcessor(cache: ThumbnailCache(diskDirectory: dir))
    return (processor, dir)
  }

  func testThumbnailReturnsImageWithinMax() async throws {
    let (processor, _) = makeProcessor()
    let data = try FixtureLoader.imageData()

    let thumbnail = await processor.thumbnail(for: data, max: NSSize(width: 100, height: 100))

    // Cache-backed path: a real downsample happened, longest side ≤ 100.
    XCTAssertNotNil(thumbnail)
    XCTAssertLessThanOrEqual(thumbnail?.size.width ?? .infinity, 100)
  }

  func testPreviewReturnsImageWithinMax() async throws {
    let (processor, _) = makeProcessor()
    let data = try FixtureLoader.imageData()

    let preview = await processor.preview(for: data, max: NSSize(width: 80, height: 80))

    // Preview is transient (no cache); still downsampled to the longest side.
    XCTAssertNotNil(preview)
    XCTAssertLessThanOrEqual(preview?.size.width ?? .infinity, 80)
  }

  func testThumbnailOfCorruptDataReturnsNil() async throws {
    let (processor, _) = makeProcessor()
    let corrupt = Data([0, 1, 2, 3])

    // The count-guard in `ImageDownsampler` keeps ImageIO from logging an
    // error here; the actor must surface nil, not crash.
    let thumbnail = await processor.thumbnail(for: corrupt, max: NSSize(width: 50, height: 50))

    XCTAssertNil(thumbnail)
  }
}
