import XCTest
@testable import Maccy

/// Image decode/decorate benchmarks — scenarios 1, 2, 6. Measures cold
/// `History.load()` (the `G-popup-open` first-frame analog: pre-BS-4 it does
/// the full fetch+sort+decorate on the main thread) plus the peak main-thread
/// stall during load. Runs in the non-blocking perf shard.
///
/// `load()` is `async`, so XCTest's sync `measure{}` doesn't apply; timing is
/// manual via `ContinuousClock` over a few iterations and printed to the log
/// (grep `PERF|` in the perf shard's log). These are BASELINE measurements —
/// they report numbers without asserting the 16 ms threshold, because the
/// pre-BS-4 baseline is *expected* to exceed it. The `< 16 ms` gate assertion
/// is added after BS-4 lands the batched background load.
@MainActor
final class ImageDecodePerformanceTests: PerformanceTestCase {
  // Scenario 1: a single large (~10 MB) image.
  func testSingleLargeImageColdLoad() async throws {
    let history = try PerfHistoryFactory.makeImages(count: 1, bucket: .tenMB, cacheDir: cacheDir)
    let measured = await measureLoad(history: history, iterations: 5)
    report(scenario: "image-single-10MB", measured: measured)
  }

  // Scenario 2: many images at the realistic cap.
  func testManyImagesColdLoad_N200() async throws {
    let history = try PerfHistoryFactory.makeImages(count: 200, bucket: .oneMB, cacheDir: cacheDir)
    let measured = await measureLoad(history: history, iterations: 3)
    report(scenario: "image-many-200", measured: measured)
  }

  // Scenario 6: many images + many long texts (worst case).
  func testMixedColdLoad_N200() async throws {
    let history = try PerfHistoryFactory.makeMixed(images: 100, texts: 100, bucket: .oneMB, cacheDir: cacheDir)
    let measured = await measureLoad(history: history, iterations: 3)
    report(scenario: "mixed-200", measured: measured)
  }

  /// Times `load()` over `iterations`, sampling the main thread throughout.
  /// Returns (average load Duration, peak main-thread gap).
  private func measureLoad(history: History, iterations: Int) async -> (Duration, TimeInterval) {
    var total = Duration.zero
    probe.start()
    for _ in 0..<iterations {
      let clock = ContinuousClock()
      let start = clock.now
      _ = try? await history.load()
      total += start.duration(to: clock.now)
    }
    probe.stop()
    return (total / iterations, probe.maxGap)
  }

  private func report(scenario: String, measured: (Duration, TimeInterval)) {
    let average = measured.0
    let maxGap = measured.1
    print("PERF|scenario=\(scenario)|load_avg=\(average)|mainThread_maxGap_s=\(maxGap)")
  }
}
