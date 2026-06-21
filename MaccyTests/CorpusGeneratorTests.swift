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
    // Generate a LARGE corpus so the A tests' N=200 image scenarios get 200+
    // distinct real photos (no cycling, no per-run regeneration when the
    // corpus is present). The main workload uses `.oneMB` (200 items), so
    // generate 200 there; larger buckets are only used by single-item tests,
    // so a smaller count keeps the Release asset size sane (`.tenMB` × 200
    // alone would be ~2GB). `.oneMB` × 200 ≈ 200MB; the rest add ~50MB.
    let bigBucket: ImageFixtureGenerator.Bucket = .oneMB
    let bigCount = 200
    for variant in 0..<bigCount {
      _ = try ImageFixtureGenerator.jpeg(bucket: bigBucket, variant: variant, cacheDir: cacheDir)
    }
    for bucket in ImageFixtureGenerator.Bucket.allCases where bucket != bigBucket {
      for variant in 0..<20 {
        _ = try ImageFixtureGenerator.jpeg(bucket: bucket, variant: variant, cacheDir: cacheDir)
      }
    }
    let contents = (try? FileManager.default.contentsOfDirectory(
      at: cacheDir, includingPropertiesForKeys: nil)) ?? []
    print("PERF|corpus-generated|dir=\(dir)|files=\(contents.count)")
  }
}
