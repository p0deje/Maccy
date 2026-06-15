import AppKit
import Foundation
import XCTest

@MainActor
final class ThumbnailCacheTests: XCTestCase {
  private func makeCache() -> (ThumbnailCache, URL) {
    let dir = FileManager.default.temporaryDirectory
      .appending(path: "ThumbnailCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let cache = ThumbnailCache(diskDirectory: dir)
    return (cache, dir)
  }

  private func fingerprint(_ value: UInt64) -> MaccyFingerprint {
    MaccyFingerprint(size: 100, hash: value)
  }

  func testFirstCallMissesThenSecondHitsMemory() async throws {
    let (cache, dir) = makeCache()
    let data = try FixtureLoader.imageData()
    let first = await cache.thumbnail(for: fingerprint(1), data: data, max: 50)
    let second = await cache.thumbnail(for: fingerprint(1), data: data, max: 50)
    XCTAssertNotNil(first)
    XCTAssertNotNil(second)
    // The miss path wrote a PNG to disk.
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertFalse(files.isEmpty, "first miss should write a disk thumbnail")
  }

  func testDiskHitAfterMemoryClear() async throws {
    let (firstCache, dir) = makeCache()
    let data = try FixtureLoader.imageData()
    let first = await firstCache.thumbnail(for: fingerprint(2), data: data, max: 40)
    XCTAssertNotNil(first)

    // Fresh instance — empty NSCache — but the same disk directory.
    let secondCache = ThumbnailCache(diskDirectory: dir)
    let second = await secondCache.thumbnail(for: fingerprint(2), data: data, max: 40)
    XCTAssertNotNil(second, "second cache should hit disk and return the thumbnail")
  }

  func testEvictMakesSubsequentCallRebuild() async throws {
    let (cache, dir) = makeCache()
    let data = try FixtureLoader.imageData()
    let itemFingerprint = fingerprint(3)
    _ = await cache.thumbnail(for: itemFingerprint, data: data, max: 30)
    let filesBefore = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertEqual(filesBefore.count, 1)

    await cache.evict(fingerprint: itemFingerprint, max: 30)
    let filesAfter = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertTrue(filesAfter.isEmpty, "evict must remove the disk file")

    let rebuilt = await cache.thumbnail(for: itemFingerprint, data: data, max: 30)
    XCTAssertNotNil(rebuilt, "thumbnail rebuilds after eviction")
  }

  func testDifferentMaxPixelSizeIsDistinctEntry() async throws {
    let (cache, dir) = makeCache()
    let data = try FixtureLoader.imageData()
    let itemFingerprint = fingerprint(4)

    let big = await cache.thumbnail(for: itemFingerprint, data: data, max: 100)
    let small = await cache.thumbnail(for: itemFingerprint, data: data, max: 50)
    XCTAssertNotNil(big)
    XCTAssertNotNil(small)

    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertEqual(files.count, 2, "different max sizes are distinct disk entries")

    // Evicting the small variant must leave the big variant on disk.
    await cache.evict(fingerprint: itemFingerprint, max: 50)
    let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertEqual(remaining.count, 1, "evict is keyed by (fingerprint, maxPixelSize)")
  }
}
