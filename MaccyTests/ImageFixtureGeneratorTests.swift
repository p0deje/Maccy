import XCTest

/// Tests for the runner-side image fixture generator. The generator itself lives
/// in the MaccyTests target (no `@testable import Maccy` needed here).
@MainActor
final class ImageFixtureGeneratorTests: XCTestCase {
  func testJPEGHitsTargetByteBucketWithinTolerance() throws {
    let cacheDir = FileManager.default.temporaryDirectory
      .appending(path: "IFGSize-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheDir) }

    let data = try ImageFixtureGenerator.jpeg(bucket: .oneMB, variant: 0, cacheDir: cacheDir)

    // Generous ±60 KB band; the quality binary search lands within ~5%.
    let target = 1_048_576
    XCTAssertGreaterThan(data.count, target - 60_000, "Undershot 1MB bucket: \(data.count) bytes")
    XCTAssertLessThan(data.count, target + 60_000, "Overshot 1MB bucket: \(data.count) bytes")
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
