import XCTest
@testable import Maccy

/// Corpus-generation entrypoint for the `generate-perf-corpus` workflow.
/// Generates the full image corpus into a FIXED, agreed-upon cache dir
/// (`~/Library/Caches/MaccyPerfCorpus`) so the workflow can tar + upload it
/// as a GitHub Release asset — no env-var plumbing through the xcodebuild test
/// host (which doesn't reliably inherit the caller's env under the
/// `enable-testing` test plan). The workflow reads from the same path.
///
/// NOT run by the main CI test shards (they download the prebuilt corpus);
/// invoked only by the dedicated `workflow_dispatch` generate job.
@MainActor
final class CorpusGeneratorTests: XCTestCase {
  /// The agreed-upon corpus dir shared with the generate workflow.
  static let corpusDir = FileManager.default.urls(
    for: .cachesDirectory, in: .userDomainMask
  ).first!.appendingPathComponent("MaccyPerfCorpus", isDirectory: true)

  func testGenerateCorpusToEnv() throws {
    let cacheDir = Self.corpusDir
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
    print("PERF|corpus-generated|dir=\(cacheDir.path)|files=\(contents.count)")
    XCTAssertGreaterThanOrEqual(contents.count, 200, "Corpus generation produced too few files")
  }
}
