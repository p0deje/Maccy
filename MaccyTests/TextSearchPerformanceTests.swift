import XCTest
@testable import Maccy

/// Text load + per-key search benchmarks — scenarios 3, 4. Scenario 3 measures
/// cold `load()` of a single long text; scenario 4 measures cold `load()` of
/// 200 long texts and the per-key search cost.
///
/// Search is measured by calling `Search().search(string:within:)` directly
/// (synchronously) rather than via `searchQuery`'s throttled didSet — the
/// `Throttler` dispatches with `asyncAfter`, so timing the setter would capture
/// only the dispatch. Calling `Search` directly is exactly the synchronous
/// main-thread work that BS-5 moves to a background actor. Baseline-only (no
/// `< 16 ms` assertion yet). Runs in the non-blocking perf shard.
@MainActor
final class TextSearchPerformanceTests: PerformanceTestCase {
  // Scenario 3: single long text — cold load.
  func testSingleLongTextColdLoad() async throws {
    let history = try PerfHistoryFactory.makeTexts(count: 1, long: true)
    let measured = await measureLoad(history: history, iterations: 5)
    report(scenario: "text-single-load", measured: measured)
  }

  // Scenario 4a: many long texts — cold load.
  func testManyLongTextsColdLoad_N200() async throws {
    let history = try PerfHistoryFactory.makeTexts(count: 200, long: true)
    let measured = await measureLoad(history: history, iterations: 3)
    report(scenario: "text-many-200-load", measured: measured)
  }

  // Scenario 4b: many long texts — per-key search (the G-search baseline).
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

  // MARK: - Shared timing helpers (duplicated from ImageDecodePerformanceTests
  // to avoid touching the in-flight Task 5; consolidate into the base later.)

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

  private func report(scenario: String, measured: (Duration, TimeInterval)) {
    let average = measured.0
    let maxGap = measured.1
    print("PERF|scenario=\(scenario)|load_avg=\(average)|mainThread_maxGap_s=\(maxGap)")
  }
}
