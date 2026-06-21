import AppKit
import XCTest

/// `method=B` performance benchmarks: the same per-item render measurement
/// (thumbnail + preview, latency) as `method=A`, but driven through the **real
/// UI pipeline** — SwiftUI `.onAppear`/`AsyncView`, real `Task` scheduling,
/// `@Observable` propagation under selection traversal. A calls `ensure*()`
/// directly; B opens the popup, opens the preview pane, and arrow-keys down
/// through the items, exactly the "pointer moves onto each candidate → render"
/// path the user wants measured.
///
/// Populate is in-process via the `MaccyPerfBulkLoad` distributed notification
/// (the app's `PerfFixtures` inserts items directly via `History.add`, the same
/// path the A tests' `PerfHistoryFactory` uses — so items render reliably and
/// populate is instant, not 1.5s-per-copy pasteboard). Renders are recorded by
/// the in-app `PerfRecorder` (completion-based — see `HistoryItemDecorator`);
/// on `MaccyPerfDump` it writes `PERF|method=B` lines to `MACCY_PERF_LOG`,
/// which the test re-prints from the test process so they land in the captured
/// xcodebuild log.
///
/// Standalone (own minimal helpers) — does not subclass `MaccyUITests` and does
/// not edit it, to avoid perturbing the existing suite. Runs in the non-blocking
/// perf shards (`continue-on-error`); a flake must never fail the gate. Image
/// fixtures are generated in-app via CoreGraphics (no binaries committed, no
/// images in logs — only `PERF|` text lines).
final class PerfRenderUITests: XCTestCase {
  private let app = XCUIApplication()

  private var perfLogURL: URL = URL(fileURLWithPath: "/dev/null")

  private static let perfReset = "org.p0deje.Maccy.Perf.reset"
  private static let perfDump = "org.p0deje.Maccy.Perf.dump"
  private static let perfOpenPreview = "org.p0deje.Maccy.Perf.openPreview"
  private static let perfBulkLoad = "org.p0deje.Maccy.Perf.bulkLoad"

  // Visit count: enough to traverse past the fold (so .onAppear fires for
  // newly-visible cells → thumbnail renders during traversal).
  private let visitCount = 20
  private let populateCount = 30

  override func setUp() {
    super.setUp()
    perfLogURL = URL.temporaryDirectory
      .appendingPathComponent("maccy-perf-\(UUID().uuidString).log")
    app.launchArguments += ["enable-testing", "MaccyPerfRecord"]
    app.launchEnvironment["MACCY_PERF_LOG"] = perfLogURL.path
    app.launch()
    if !app.statusItems.firstMatch.waitForExistence(timeout: 10) {
      XCTFail("Maccy status item did not appear")
    }
  }

  override func tearDown() {
    app.terminate()
    super.tearDown()
  }

  // MARK: - Scenarios

  /// Many images: visit the first 20 with the preview pane open. Thumbnail
  /// renders fire as cells scroll into view; preview renders fire as the lead
  /// selection moves (the `.id(item.id)` fix makes PreviewItemView refresh per
  /// selection).
  func testImageRenderB() throws {
    driveTraversal(category: "image", openPreview: true)
  }

  /// Many long texts: text items have no image data, so neither thumbnail nor
  /// preview image generation runs — the dump reports `items=0` for both ops,
  /// honestly confirming text traversal incurs no image-decode work (the
  /// image-vs-text contrast, matching A's "text all 0").
  func testTextRenderB() throws {
    driveTraversal(category: "text", openPreview: false)
  }

  /// Many images + many long texts interleaved: visit the first 20. Image
  /// cells render (thumbnail on scroll, preview on selection); text cells do
  /// not. Tests the mixed-pipeline worst case.
  func testMixedRenderB() throws {
    driveTraversal(category: "mixed", openPreview: true)
  }

  // MARK: - Traversal driver

  /// Populates via in-process bulk-load, opens the popup, resets the recorder
  /// (discards the populate + popup-open cold burst), optionally opens the
  /// preview pane, arrow-keys down `visitCount` times, then dumps and re-prints
  /// the `PERF|` lines from the log file.
  private func driveTraversal(category: String, openPreview: Bool) {
    // In-process populate (instant, reliable) — bypasses the 1.5s-per-copy
    // pasteboard poll.
    post(Self.perfBulkLoad, userInfo: ["count": populateCount, "category": category])
    usleep(500_000)

    // Open popup (selects the first item → preview pane can open).
    app.statusItems.firstMatch.click()
    if !app.staticTexts.firstMatch.waitForExistence(timeout: 5) {
      XCTFail("Maccy did not pop up")
    }
    usleep(500_000)
    post(Self.perfReset)

    if openPreview {
      post(Self.perfOpenPreview)
      usleep(600_000)
    }

    for _ in 0..<visitCount {
      app.typeKey(.downArrow, modifierFlags: [])
      usleep(150_000)
    }
    // Let the final off-main decodes publish back to main.
    usleep(2_000_000)

    post(Self.perfDump, userInfo: ["category": category])
    usleep(500_000)
    printPerfLines(from: perfLogURL)
  }

  // MARK: - Helpers

  private func post(_ name: String, userInfo: [String: Any]? = nil) {
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name(name),
      object: nil,
      userInfo: userInfo,
      deliverImmediately: true
    )
    usleep(300_000)
  }

  private func printPerfLines(from url: URL) {
    let deadline = Date().addingTimeInterval(5)
    var content: String?
    while Date() < deadline {
      if let data = try? String(contentsOf: url, encoding: .utf8), !data.isEmpty {
        content = data
        break
      }
      usleep(200_000)
    }
    guard let content else {
      print("PERF|category=none|method=B|op=none|items=0|note=no-perf-log-written")
      return
    }
    content.split(separator: "\n").forEach { print($0) }
  }
}
