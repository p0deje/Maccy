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

  // MARK: - Probe self-test (foundation check)

  /// Validates `MainThreadProbe` detects a main-thread stall. Blocks main
  /// synchronously for ~50 ms (the sampler's ticks queue up while main is
  /// blocked), then `await Task.yield()` so main processes those queued ticks —
  /// their `processedAt - dispatchedAt` delay must reflect the stall. If this
  /// fails, every mainThread measurement below is meaningless — fix the probe.
  func testProbeDetectsSynchronousMainStall() async {
    probe.start()
    let until = Date().addingTimeInterval(0.05)
    while Date() < until {}
    await Task.yield()
    probe.stop()
    XCTAssertGreaterThan(
      probe.maxGap,
      0.04,
      "Probe must detect the 50 ms main stall; got \(probe.maxGap)s"
    )
  }

  // MARK: - Per-item render (first 20) — the "pointer moves onto each item" analog

  /// Scenario: 200 images loaded, then "visit" the first 20 one by one. For
  /// each item we trigger the real render paths — thumbnail (`ensureThumbnail`
  /// → await the generation task) and preview (`asyncGetPreviewImage`) — timing
  /// each and sampling the main thread, exactly the work that fires when the
  /// pointer/selection lands on an item. `method=A` = decode-level (direct
  /// call); the BS-4/5 fixes must keep each item's worstBlockMs small.
  func testImageRenderFirst20() async throws {
    let history = try PerfHistoryFactory.makeImages(count: 200, bucket: .oneMB, cacheDir: cacheDir)
    _ = try? await history.load()
    let first20 = Array(history.items.prefix(20))

    let thumbnail = await measurePerItemRender(first20) { decorator in
      decorator.ensureThumbnailImage()
      _ = await decorator.thumbnailImageGenerationTask?.value
    }
    let preview = await measurePerItemRender(first20) { decorator in
      _ = await decorator.asyncGetPreviewImage()
    }

    printPERF(category: "image", method: "A", operation: "thumbnail", result: thumbnail)
    printPERF(category: "image", method: "A", operation: "preview", result: preview)
  }

  /// Scenario: 200 long texts, visit the first 20. Text items have no image
  /// data, so `ensureThumbnailImage`/`asyncGetPreviewImage` early-return and the
  /// per-item cost is just navigation/selection + on-main title work — the
  /// contrast with `image` shows where decode cost lives.
  func testTextRenderFirst20() async throws {
    let history = try PerfHistoryFactory.makeTexts(count: 200, long: true)
    _ = try? await history.load()
    let first20 = Array(history.items.prefix(20))

    let thumbnail = await measurePerItemRender(first20) { decorator in
      decorator.ensureThumbnailImage()
      _ = await decorator.thumbnailImageGenerationTask?.value
    }
    let preview = await measurePerItemRender(first20) { decorator in
      _ = await decorator.asyncGetPreviewImage()
    }

    printPERF(category: "text", method: "A", operation: "thumbnail", result: thumbnail)
    printPERF(category: "text", method: "A", operation: "preview", result: preview)
  }

  /// Scenario: mixed images + long texts (interleaved so the first 20 contain
  /// both types), visit the first 20.
  func testMixedRenderFirst20() async throws {
    let history = try PerfHistoryFactory.makeMixed(
      images: 100, texts: 100, bucket: .oneMB, cacheDir: cacheDir
    )
    _ = try? await history.load()
    let first20 = Array(history.items.prefix(20))

    let thumbnail = await measurePerItemRender(first20) { decorator in
      decorator.ensureThumbnailImage()
      _ = await decorator.thumbnailImageGenerationTask?.value
    }
    let preview = await measurePerItemRender(first20) { decorator in
      _ = await decorator.asyncGetPreviewImage()
    }

    printPERF(category: "mixed", method: "A", operation: "thumbnail", result: thumbnail)
    printPERF(category: "mixed", method: "A", operation: "preview", result: preview)
  }

  // MARK: - Per-item measurement helpers

  private struct PerItemResult {
    let perItemMs: [Double]
    let avgMs: Double
    let maxMs: Double
    let totalMs: Double
    let worstBlockMs: Double
    let totalBlockMs: Double
  }

  /// Runs `render` once per decorator (sequentially), timing each and sampling
  /// the main thread (reset between items so maxGap is per-item). The probe
  /// runs for the whole loop; reset+read bracket each item.
  private func measurePerItemRender(
    _ decorators: [HistoryItemDecorator],
    render: (HistoryItemDecorator) async -> Void
  ) async -> PerItemResult {
    var perItemMs: [Double] = []
    var blockMs: [Double] = []
    probe.start()
    for decorator in decorators {
      probe.reset()
      let clock = ContinuousClock()
      let start = clock.now
      await render(decorator)
      let elapsed = start.duration(to: clock.now)
      perItemMs.append(Self.milliseconds(elapsed))
      blockMs.append(probe.maxGap * 1000)
    }
    probe.stop()

    let total = perItemMs.reduce(0, +)
    return PerItemResult(
      perItemMs: perItemMs,
      avgMs: perItemMs.isEmpty ? 0 : total / Double(perItemMs.count),
      maxMs: perItemMs.max() ?? 0,
      totalMs: total,
      worstBlockMs: blockMs.max() ?? 0,
      totalBlockMs: blockMs.reduce(0, +)
    )
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1000
      + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }

  /// Emits one machine-parseable `PERF|…` line. Multi-line concatenation to
  /// keep each source line under SwiftLint's line_length limit.
  private func printPERF(category: String, method: String, operation: String, result: PerItemResult) {
    let perItem = result.perItemMs
      .map { String(format: "%.2f", $0) }
      .joined(separator: ",")
    let line = "PERF|category=\(category)|method=\(method)|op=\(operation)" +
      "|items=\(result.perItemMs.count)|perItemMs=[\(perItem)]" +
      "|avgMs=\(String(format: "%.2f", result.avgMs))" +
      "|maxMs=\(String(format: "%.2f", result.maxMs))" +
      "|totalMs=\(String(format: "%.2f", result.totalMs))" +
      "|worstBlockMs=\(String(format: "%.2f", result.worstBlockMs))" +
      "|totalBlockMs=\(String(format: "%.2f", result.totalBlockMs))"
    print(line)
  }
}
