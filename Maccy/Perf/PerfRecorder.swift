#if DEBUG
import Foundation

/// In-app render instrumentation for the `method=B` performance benchmarks
/// (`MaccyUITests/PerfRenderUITests`). B measures the same per-item render
/// (thumbnail + preview, latency + main-thread block) as the `method=A`
/// direct-call benchmarks, but driven through the **real UI pipeline** —
/// SwiftUI `.onAppear`/`AsyncView`, real `Task` scheduling, `@Observable`
/// propagation under selection traversal — which A's synthetic `ensure*()`
/// call cannot exercise.
///
/// Enabled only when the app is launched with the `MaccyPerfRecord` argument
/// (DEBUG builds only; the whole type is `#if DEBUG`, and call sites in
/// `HistoryItemDecorator` are `#if DEBUG`-gated, so Release ships zero
/// instrumentation and blocking UI shards — which run DEBUG without the arg —
/// hit the plain render path byte-for-byte). The UI test sets
/// `app.launchEnvironment["MACCY_PERF_LOG"]` to a temp file path, drives the
/// traversal, then posts the `MaccyPerfDump` distributed notification; the app
/// writes `PERF|…` lines to that file and the test re-prints them from the test
/// process so they land in the captured `xcodebuild` log (app-stdout forwarding
/// across the `XCUIApplication` process boundary is not guaranteed).
///
/// `reset()` (on `MaccyPerfReset`) discards the popup-open cold-render burst so
/// B measures the traversal. PERF lines are text only — no image data —
/// satisfying "images must not end up in logs".
@MainActor
final class PerfRecorder {
  static let shared = PerfRecorder()

  /// `true` only when launched with `MaccyPerfRecord`. Call sites branch on this
  /// so the disabled path (all normal runs + blocking UI shards) incurs no
  /// timing overhead.
  static let enabled: Bool = CommandLine.arguments.contains("MaccyPerfRecord")

  private struct RenderEvent {
    let latencyMs: Double
    let mainBlockMs: Double
  }

  private var thumbnailEvents: [RenderEvent] = []
  private var previewEvents: [RenderEvent] = []

  private init() {}

  /// Clears recorded events — posted as `MaccyPerfReset` before the traversal
  /// so the popup-open cold-render burst is excluded from the measurement.
  func reset() {
    thumbnailEvents.removeAll()
    previewEvents.removeAll()
  }

  /// Records one thumbnail render. `mainBlock` = the on-main synchronous portion
  /// (total − off-main decode await); the decode itself runs on the
  /// `ImageProcessor` actor, so this is ~0 when BS-3's off-main decode holds.
  func recordThumbnail(latency: Duration, mainBlock: Duration) {
    guard Self.enabled else { return }
    thumbnailEvents.append(RenderEvent(
      latencyMs: Self.millis(latency),
      mainBlockMs: Self.millis(mainBlock)
    ))
  }

  /// Records one preview render (selection-driven, via `asyncGetPreviewImage`).
  func recordPreview(latency: Duration, mainBlock: Duration) {
    guard Self.enabled else { return }
    previewEvents.append(RenderEvent(
      latencyMs: Self.millis(latency),
      mainBlockMs: Self.millis(mainBlock)
    ))
  }

  /// Emits one `PERF|…` line per op (thumbnail, preview) to the file at
  /// `MACCY_PERF_LOG`. Always emits both lines (with `items=0` when no events
  /// were recorded for that op, e.g. text traversal produces no image renders)
  /// so the file is non-empty and the UI test's read is reliable. No-op when
  /// not enabled or the path is unset. Best-effort: never throws.
  func dump(category: String) {
    guard Self.enabled else { return }
    guard let path = ProcessInfo.processInfo.environment["MACCY_PERF_LOG"] else {
      return
    }
    let lines = [
      formatLine(category: category, op: "thumbnail", events: thumbnailEvents),
      formatLine(category: category, op: "preview", events: previewEvents)
    ]
    let payload = lines.joined(separator: "\n") + "\n"
    try? payload.write(toFile: path, atomically: true, encoding: .utf8)
  }

  // MARK: - Private

  private func formatLine(category: String, op: String, events: [RenderEvent]) -> String {
    let count = events.count
    let latency = events
      .map { String(format: "%.2f", $0.latencyMs) }
      .joined(separator: ",")
    let mainBlock = events
      .map { String(format: "%.2f", $0.mainBlockMs) }
      .joined(separator: ",")
    let avg = count > 0
      ? events.reduce(0) { $0 + $1.latencyMs } / Double(count)
      : 0
    let maxLatency = events.map(\.latencyMs).max() ?? 0
    let maxBlock = events.map(\.mainBlockMs).max() ?? 0
    let totalBlock = events.reduce(0) { $0 + $1.mainBlockMs }
    return "PERF|category=\(category)|method=B|op=\(op)"
      + "|items=\(count)"
      + "|latencyMs=[\(latency)]|latencyAvg=\(String(format: "%.2f", avg))"
      + "|latencyMax=\(String(format: "%.2f", maxLatency))"
      + "|mainBlockMs=[\(mainBlock)]|mainBlockMax=\(String(format: "%.2f", maxBlock))"
      + "|mainBlockTotal=\(String(format: "%.2f", totalBlock))"
  }

  private static func millis(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) * 1000
      + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }
}
#endif
