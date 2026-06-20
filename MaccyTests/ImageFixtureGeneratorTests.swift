import XCTest

/// Tests for the runner-side image fixture generator. The generator itself lives
/// in the MaccyTests target (no `@testable import Maccy` needed here).
@MainActor
final class ImageFixtureGeneratorTests: XCTestCase {
  func testJPEGProducesApproximatelyBucketSizedImage() throws {
    let cacheDir = FileManager.default.temporaryDirectory
      .appending(path: "IFGSize-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheDir) }

    let data = try ImageFixtureGenerator.jpeg(bucket: .oneMB, variant: 0, cacheDir: cacheDir)

    // Approximate sizing: a JPEG's byte count varies with content compressibility
    // (real photo vs synthetic fallback) and is bounded by the canvas at max
    // quality, so assert a factor-of-3 band around the 1 MB target rather than a
    // tight tolerance. The decode benchmark cares about pixel dimensions (a
    // range across buckets), not exact bytes.
    let target = 1_048_576
    XCTAssertGreaterThan(data.count, target / 3, "Undershot 1MB bucket (expect ~1MB): \(data.count) bytes")
    XCTAssertLessThan(data.count, target * 3, "Overshot 1MB bucket (expect ~1MB): \(data.count) bytes")
  }

  func testJPEGIsDeterministicAcrossCalls() throws {
    let cacheDir = FileManager.default.temporaryDirectory
      .appending(path: "IFGDet-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheDir) }

    let first = try ImageFixtureGenerator.jpeg(bucket: .halfMB, variant: 1, cacheDir: cacheDir)
    let second = try ImageFixtureGenerator.jpeg(bucket: .halfMB, variant: 1, cacheDir: cacheDir)

    XCTAssertEqual(first, second, "Same bucket/variant must produce identical bytes (seeded + cached).")
  }
}
