import XCTest
@testable import Maccy

/// Text load and per-key search benchmarks.
///
/// The load scenarios measure cold `load()` of one and many long texts. The
/// search scenarios measure per-key matching on the off-main `SearchActor` — the
/// shipped path — across n=200 (baseline) and n=1000 corpora whose items each
/// carry the heavy-text body. The actor runs off-main, so the main-thread gap
/// during a search should stay well under the 16ms/keystroke budget; the
/// recorded actor latency is the input to the index decision (add a trigram
/// index only if the linear scan proves too slow). These run in a non-blocking
/// performance shard.
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

  /// Per-key actor search across n=200 long-text bodies (baseline). Measures the
  /// off-main actor latency and the main-thread gap during the search.
  func testActorSearchPerKey_N200() async throws {
    let measured = try await measureActorSearch(count: 200, mode: .mixed)
    let average = measured.0
    let gap = measured.1
    print("PERF|scenario=text-actor-200-search|searchPerKey_avg=\(average)|mainThread_maxGap_s=\(gap)")
  }

  /// Per-key actor search across n=1000 long-text bodies — the latency gate for
  /// the index decision. The search runs off-main, so the main thread must stay
  /// under the 16ms/keystroke budget. The recorded actor latency decides whether
  /// a trigram index is worth its memory cost: a fast linear scan keeps the
  /// no-index design; a slow one motivates adding one.
  func testActorSearchPerKey_N1000() async throws {
    let measured = try await measureActorSearch(count: 1000, mode: .mixed)
    let average = measured.0
    let gap = measured.1
    print("PERF|scenario=text-actor-1000-search|searchPerKey_avg=\(average)|mainThread_maxGap_s=\(gap)")
    XCTAssertLessThan(gap, 0.016, "main-thread budget exceeded at n=1000")
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

  /// Builds a corpus of `count` items each carrying the heavy-text body (capped
  /// to `TextLimits.searchBody`), then measures the per-key `SearchActor` search
  /// latency (off-main) and the worst main-thread gap during the search. Bodies
  /// share storage (String copy-on-write), so corpus memory stays bounded while
  /// the scan cost reflects a realistic full corpus.
  private func measureActorSearch(count: Int, mode: Search.Mode) async throws -> (Duration, TimeInterval) {
    let heavy = try Data(contentsOf: FixtureLoader.heavyTextURL)
    let text = String(data: heavy, encoding: .utf8) ?? ""
    let body = String(text.prefix(TextLimits.searchBody))
    let corpus = (0..<count).map { index in
      SearchCorpusItem(id: UUID(), title: "clip \(index)", body: body)
    }
    let searchActor = SearchActor()
    let queries = ["the", "lorem", "xyzzy", "a"]

    var total = Duration.zero
    probe.start()
    for query in queries {
      let start = ContinuousClock().now
      _ = await searchActor.search(query: query, within: corpus, mode: mode)
      total += start.duration(to: ContinuousClock().now)
    }
    let gap = await probe.maxGapAsync()
    probe.stop()
    return (total / queries.count, gap)
  }

  /// Emits a `PERF|` line carrying the average duration and worst main-thread gap.
  private func report(scenario: String, measured: (Duration, TimeInterval)) {
    let average = measured.0
    let maxGap = measured.1
    print("PERF|scenario=\(scenario)|load_avg=\(average)|mainThread_maxGap_s=\(maxGap)")
  }
}
