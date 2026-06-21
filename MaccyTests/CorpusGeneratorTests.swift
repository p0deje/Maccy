import XCTest
@testable import Maccy

/// Corpus-generation entrypoint for the `generate-perf-corpus` workflow. When
/// run with `MACCY_PERF_FIXTURES` set, generates the full image corpus (all
/// buckets × enough variants) into that dir so the workflow can upload it as a
/// GitHub Release asset (shared across runs — "generate once, reuse, not in
/// git"). NOT run by the main CI test shards (they download the prebuilt
/// corpus); invoked only by the dedicated `workflow_dispatch` generate job.
///
/// Generating enough variants to cover the worst-case A test (200 items) would
/// be slow + huge; instead we generate a representative set per bucket and the
/// tests cycle `variant % count` (see `ImageFixtureGenerator.jpeg`'s
/// `variant % sourceImages.count`).
@MainActor
final class CorpusGeneratorTests: XCTestCase {
  func testGenerateCorpusToEnv() throws {
    let dir = try XCTUnwrap(
      ProcessInfo.processInfo.environment["MACCY_PERF_FIXTURES"],
      "MACCY_PERF_FIXTURES must be set (run only via the generate-perf-corpus workflow)"
    )
    let cacheDir = URL(fileURLWithPath: dir)
    try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    // Generate a spread of variants per bucket — enough for the B benchmark's
    // 30 items + the A tests' 200 (cycled). Real CC0 photos, cropped to each
    // bucket's byte target via JPEG-quality binary search.
    let variantsPerBucket = 30
    for bucket in ImageFixtureGenerator.Bucket.allCases {
      for variant in 0..<variantsPerBucket {
        _ = try ImageFixtureGenerator.jpeg(bucket: bucket, variant: variant, cacheDir: cacheDir)
      }
    }
    let count = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil))?.count ?? 0
    print("PERF|corpus-generated|dir=\(dir)|files=\(count)")
  }
}
