import XCTest
@testable import Maccy

/// Text load and per-key search benchmarks.
///
/// Scenario 3 measures a cold `load()` of a single long text; scenario 4
/// measures a cold `load()` of 200 long texts and the per-key search cost. Search
/// is measured by calling `Search().search(string:within:)` directly rather than
/// through `searchQuery`'s throttled `didSet` — the throttler dispatches via
/// `asyncAfter`, so timing the setter would capture only the dispatch. Calling
/// `Search` directly captures exactly the synchronous main-thread search work.
/// These are baseline measurements only (no frame-budget assertion) and run in a
/// non-blocking performance shard.
@MainActor
final class TextSearchPerformanceTests: PerformanceTestCase {
  /// Cold `load()` of a single long text.
  func testSingleLongTextColdLoad() async throws {
    let history = try PerfHistoryFactory.makeTexts(count: 1, long: true)
    let measured = await measureLoad(history: history, iterations: 5)
    report(scenario: "text-single-load", measured: measured)
  }

  /// Cold `load()` of many long texts.
  func testManyLongTextsColdLoad_N200() async throws {
    let history = try PerfHistoryFactory.makeTexts(count: 200, long: true)
    let measured = await measureLoad(history: history, iterations: 3)
    report(scenario: "text-many-200-load", measured: measured)
  }

  /// Per-key search cost across a corpus of long texts.
  func testManyLongTextsSearchPerKey_N200() async throws {
    let history = try PerfHistoryFactory.makeTexts(count: 200, long: true)
    _ = try? await history.load()
    let searchable = history.all
    let search = Search()
    let queries = ["the", "a", "lorem", "xyzzy"]

    var total = Duration.zero
    probe.start()
    for query in queries {
      let clock = ContinuousClock()
      let start = clock.now
      _ = search.search(string: query, within: searchable)
      total += start.duration(to: clock.now)
    }
    let gap = await probe.maxGapAsync()
    probe.stop()

    let average = total / queries.count
    print("PERF|scenario=text-many-200-search|searchPerKey_avg=\(average)|mainThread_maxGap_s=\(gap)")
  }

  // MARK: - Shared timing helpers

  /// Measures the average `load()` duration over `iterations` runs while sampling
  /// the worst main-thread stall, returning both.
  private func measureLoad(history: History, iterations: Int) async -> (Duration, TimeInterval) {
    var total = Duration.zero
    probe.start()
    for _ in 0..<iterations {
      let clock = ContinuousClock()
      let start = clock.now
      _ = try? await history.load()
      total += start.duration(to: clock.now)
    }
    let gap = await probe.maxGapAsync()
    probe.stop()
    return (total / iterations, gap)
  }

  /// Emits a `PERF|` line carrying the average duration and worst main-thread gap.
  private func report(scenario: String, measured: (Duration, TimeInterval)) {
    let average = measured.0
    let maxGap = measured.1
    print("PERF|scenario=\(scenario)|load_avg=\(average)|mainThread_maxGap_s=\(maxGap)")
  }
}
