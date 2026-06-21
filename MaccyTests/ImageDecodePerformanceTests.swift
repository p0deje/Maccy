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
  /// Returns (average load Duration, peak main-thread gap). The gap is read via
  /// `maxGapAsync()` so the probe's queued ticks are drained on main first — a
  /// sync read here returns 0.0 (the sampler ticks dispatch via
  /// `DispatchQueue.main.async` and only record their delay once main runs them).
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

  // MARK: - G-copy (live per-copy path): History.consume → reconcileWithStore

  /// `G-copy` gate — the LIVE per-copy main-thread cost. In production the
  /// `BackgroundClipboardIngestor` actor commits each copy off-main, then emits
  /// `.added(snapshot)` which hops back to main into `History.consume` →
  /// `reconcileWithStore` (`History.swift:291-324`): a **full `context.fetch` +
  /// two-pass `sorter.sort` over ALL items on main, every copy** (`:294`). That
  /// is the per-copy jank the user feels; this test measures it directly by
  /// driving `consume(.added(...))` (bypassing the 1.5s pasteboard poll so we
  /// time the main work, not the sleep). The legacy `findSimilarItem`/`History.add`
  /// path is dead in production — see the audit; this measures the real path.
  ///
  /// Pre-populates 200 items, then simulates 20 copies (insert one item into the
  /// main context + save, then `consume(.added(snapshot))`), timing each consume
  /// + sampling main-thread occupancy across the burst.
  func testGCopyPerCopyConsume_N200() async throws {
    let history = try PerfHistoryFactory.makeTexts(count: 200, long: false)
    _ = try? await history.load()

    let clock = ContinuousClock()
    var perCopyMs: [Double] = []
    probe.start()
    for index in 0..<20 {
      // Insert a new item into the main context (what the actor's background
      // save merges in), then drive the live consume path.
      let item = HistoryBuilder()
        .withContent(type: "public.utf8-plain-text", value: Data("copy #\(index)".utf8))
        .withCopiedAt(Date(timeIntervalSince1970: 1_700_000_000 + Double(index)))
        .build()
      Storage.shared.context.insert(item)
      try? Storage.shared.context.save()
      let snapshot = snapshot(of: item)
      let start = clock.now
      history.consume(.added(snapshot))
      perCopyMs.append(Self.milliseconds(start.duration(to: clock.now)))
    }
    let gap = await probe.maxGapAsync()
    probe.stop()

    let avg = perCopyMs.reduce(0, +) / Double(perCopyMs.count)
    let maxCopy = perCopyMs.max() ?? 0
    let perCopy = perCopyMs.map { String(format: "%.2f", $0) }.joined(separator: ",")
    print("PERF|gate=G-copy|method=A|op=consume|items=\(perCopyMs.count)" +
      "|perCopyMs=[\(perCopy)]|perCopyAvgMs=\(String(format: "%.2f", avg))" +
      "|perCopyMaxMs=\(String(format: "%.2f", maxCopy))" +
      "|mainThread_maxGap_s=\(gap)")
  }

  // MARK: - Probe self-test (foundation check)

  /// Validates `MainThreadProbe` detects a main-thread stall. Blocks main
  /// synchronously for ~50 ms (the sampler's ticks queue up while main is
  /// blocked), then `await Task.yield()` so main processes those queued ticks —
  /// their `processedAt - dispatchedAt` delay must reflect the stall. If this
  /// fails, every mainThread measurement below is meaningless — fix the probe.
  func testProbeDetectsSynchronousMainStall() async {
    probe.start()
    // Block main ~80 ms (longer than one frame + sampler jitter). The sampler
    // dispatches ticks during this block; maxGapAsync drains them and the
    // recorded delay must reflect the stall. Threshold 0.02s is well below the
    // ~80 ms block but well above noise, so the test is robust to sampler
    // timing on the loaded headless runner (an earlier 0.04 threshold flaked
    // when the first tick landed ~38 ms in).
    let until = Date().addingTimeInterval(0.08)
    while Date() < until {}
    let gap = await probe.maxGapAsync()
    probe.stop()
    XCTAssertGreaterThan(
      gap,
      0.02,
      "Probe must detect the ~80 ms main stall; got \(gap)s"
    )
  }

  // MARK: - Per-item render (first 20) — the "pointer moves onto each item" analog

  /// Per-item render: for each of the first 20 items we run the real render
  /// paths — thumbnail (`ensureThumbnailImage` → await the generation task) and
  /// preview (`ensurePreviewImage` → await the task) — exactly the work that
  /// fires when the pointer/selection lands on an item. `method=A` = decode-level
  /// (direct call). Per item we record **latency** (total: sync kick + the
  /// off-main decode await) and **mainBlock** (the synchronous main-thread
  /// portion — the `ensure*` kick; the decode itself is off-main via the
  /// ImageProcessor actor, so any on-main cost shows here). BS-4/5 must keep
  /// mainBlock small per item.
  func testImageRenderFirst20() async throws {
    let history = try PerfHistoryFactory.makeImages(count: 200, bucket: .oneMB, cacheDir: cacheDir)
    _ = try? await history.load()
    let first20 = Array(history.items.prefix(20))

    let thumbnail = await measurePerItemRender(
      first20,
      kick: { $0.ensureThumbnailImage() },
      completion: { _ = await $0.thumbnailImageGenerationTask?.value }
    )
    let preview = await measurePerItemRender(
      first20,
      kick: { $0.ensurePreviewImage() },
      completion: { _ = await $0.previewImageGenerationTask?.value }
    )

    printPERF(category: "image", method: "A", operation: "thumbnail", result: thumbnail)
    printPERF(category: "image", method: "A", operation: "preview", result: preview)
  }

  /// Scenario: 200 long texts, visit the first 20. Text items have no image
  /// data, so `ensure*` early-return and both latency + mainBlock are ~0 — the
  /// contrast with `image` shows where decode cost lives.
  func testTextRenderFirst20() async throws {
    let history = try PerfHistoryFactory.makeTexts(count: 200, long: true)
    _ = try? await history.load()
    let first20 = Array(history.items.prefix(20))

    let thumbnail = await measurePerItemRender(
      first20,
      kick: { $0.ensureThumbnailImage() },
      completion: { _ = await $0.thumbnailImageGenerationTask?.value }
    )
    let preview = await measurePerItemRender(
      first20,
      kick: { $0.ensurePreviewImage() },
      completion: { _ = await $0.previewImageGenerationTask?.value }
    )

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

    let thumbnail = await measurePerItemRender(
      first20,
      kick: { $0.ensureThumbnailImage() },
      completion: { _ = await $0.thumbnailImageGenerationTask?.value }
    )
    let preview = await measurePerItemRender(
      first20,
      kick: { $0.ensurePreviewImage() },
      completion: { _ = await $0.previewImageGenerationTask?.value }
    )

    printPERF(category: "mixed", method: "A", operation: "thumbnail", result: thumbnail)
    printPERF(category: "mixed", method: "A", operation: "preview", result: preview)
  }

  // MARK: - Per-item measurement helpers

  private struct PerItemResult {
    let latencyMs: [Double]   // total render time per item (sync kick + off-main await)
    let mainBlockMs: [Double]  // synchronous main-thread time per item (the ensure* kick)
    var latencyAvg: Double { latencyMs.isEmpty ? 0 : latencyMs.reduce(0, +) / Double(latencyMs.count) }
    var latencyMax: Double { latencyMs.max() ?? 0 }
    var mainBlockMax: Double { mainBlockMs.max() ?? 0 }
    var mainBlockTotal: Double { mainBlockMs.reduce(0, +) }
  }

  /// Runs `kick` (synchronous, on main) then `completion` (async — the off-main
  /// decode await) once per decorator, timing each. `mainBlock` = the kick time
  /// (the on-main portion); `latency` = kick + await.
  private func measurePerItemRender(
    _ decorators: [HistoryItemDecorator],
    kick: (HistoryItemDecorator) -> Void,
    completion: (HistoryItemDecorator) async -> Void
  ) async -> PerItemResult {
    let clock = ContinuousClock()
    var latencyMs: [Double] = []
    var mainBlockMs: [Double] = []
    for decorator in decorators {
      let totalStart = clock.now
      let mainStart = clock.now
      kick(decorator)
      let mainElapsed = mainStart.duration(to: clock.now)
      await completion(decorator)
      let totalElapsed = totalStart.duration(to: clock.now)
      latencyMs.append(Self.milliseconds(totalElapsed))
      mainBlockMs.append(Self.milliseconds(mainElapsed))
    }
    return PerItemResult(latencyMs: latencyMs, mainBlockMs: mainBlockMs)
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let components = duration.components
    // `Duration.components` = (seconds, attoseconds) where attoseconds is the
    // *sub-second* part (1 atto = 1e-18 s). To get MILLISECONDS: seconds×1000
    // + attoseconds/1e15. The prior /1e18 divided by 1000 too many, reporting
    // ~0.06 "ms" for a 60 ms duration (1000× underreport). See audit 2026-06-21.
    return Double(components.seconds) * 1000
      + Double(components.attoseconds) / 1_000_000_000_000_000
  }

  /// Emits one machine-parseable `PERF|…` line. Multi-line concatenation to
  /// keep each source line under SwiftLint's line_length limit.
  private func printPERF(category: String, method: String, operation: String, result: PerItemResult) {
    let latency = result.latencyMs
      .map { String(format: "%.2f", $0) }
      .joined(separator: ",")
    let mainBlock = result.mainBlockMs
      .map { String(format: "%.2f", $0) }
      .joined(separator: ",")
    let line = "PERF|category=\(category)|method=\(method)|op=\(operation)" +
      "|items=\(result.latencyMs.count)" +
      "|latencyMs=[\(latency)]|latencyAvg=\(String(format: "%.2f", result.latencyAvg))" +
      "|latencyMax=\(String(format: "%.2f", result.latencyMax))" +
      "|mainBlockMs=[\(mainBlock)]|mainBlockMax=\(String(format: "%.2f", result.mainBlockMax))" +
      "|mainBlockTotal=\(String(format: "%.2f", result.mainBlockTotal))"
    print(line)
  }
}
