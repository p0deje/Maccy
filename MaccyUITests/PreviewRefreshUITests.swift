import AppKit
import XCTest

/// Regression test for stale preview rendering across navigation.
///
/// `PreviewItemView` is keyed by item id in `SlideoutContentView`, so each
/// selection change tears down and recreates the view and re-runs
/// `asyncGetPreviewImage`. This test populates image items via the in-process
/// bulk-load bridge (the pasteboard path is unreliable on the headless runner
/// and can leave history empty), opens the popup and preview pane, navigates
/// down, and asserts the in-app `PerfRecorder` recorded more than one preview
/// render — i.e. the preview refreshed across navigation rather than sticking on
/// the first item.
///
/// Uses the `MaccyPerfRecord` instrumentation bridge and runs in the
/// performance-image shard.
@MainActor
final class PreviewRefreshUITests: XCTestCase {
  private let app = XCUIApplication()
  private var perfLogURL: URL = URL(fileURLWithPath: "/dev/null")

  private static let perfReset = "org.p0deje.Maccy.Perf.reset"
  private static let perfDump = "org.p0deje.Maccy.Perf.dump"
  private static let perfOpenPreview = "org.p0deje.Maccy.Perf.openPreview"
  private static let perfBulkLoad = "org.p0deje.Maccy.Perf.bulkLoad"

  /// Configures perf logging, launches the app, and waits for the status item.
  override func setUp() async throws {
    try await super.setUp()
    perfLogURL = URL.temporaryDirectory
      .appendingPathComponent("maccy-preview-\(UUID().uuidString).log")
    app.launchArguments += ["enable-testing", "MaccyPerfRecord"]
    app.launchEnvironment["MACCY_PERF_LOG"] = perfLogURL.path
    app.launch()
    if !app.statusItems.firstMatch.waitForExistence(timeout: 10) {
      XCTFail("Maccy status item did not appear")
    }
  }

  /// Terminates the app after each test.
  override func tearDown() async throws {
    app.terminate()
    try await super.tearDown()
  }

  /// Navigating across distinct items must produce more than one preview render.
  func testPreviewRefreshesAcrossNavigation() throws {
    // Reliable in-process populate (the pasteboard path left history.items empty
    // on the headless runner → 0 renders; the bulk-load bridge inserts directly
    // into the context + one load).
    post(Self.perfBulkLoad, userInfo: ["count": 8, "category": "image"])
    usleep(800_000)

    // Open popup (selects the first item → preview pane can open).
    app.statusItems.firstMatch.click()
    if !app.staticTexts.firstMatch.waitForExistence(timeout: 5) {
      XCTFail("Maccy did not pop up")
    }
    usleep(500_000)
    post(Self.perfReset)
    post(Self.perfOpenPreview)
    // Let the first item's preview decode + render settle.
    usleep(1_500_000)

    // Navigate down 3 distinct items, slowly enough that each preview's off-main
    // decode completes.
    for _ in 0..<3 {
      app.typeKey(.downArrow, modifierFlags: [])
      usleep(1_000_000)
    }
    usleep(2_000_000) // let the final off-main decode publish.

    post(Self.perfDump, userInfo: ["category": "preview-refresh"])
    usleep(500_000)

    let previewCount = readPreviewCount(from: perfLogURL)
    XCTAssertGreaterThan(
      previewCount,
      1,
      "Preview did not refresh across navigation (preview renders = \(previewCount)); "
        + "the preview-stale bug may have regressed."
    )
  }

  // MARK: - Helpers

  /// Posts a distributed notification to the running app and brief pauses for delivery.
  private func post(_ name: String, userInfo: [String: Any]? = nil) {
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name(name),
      object: nil,
      userInfo: userInfo,
      deliverImmediately: true
    )
    usleep(300_000)
  }

  /// Reads the `items=<n>` from the `op=preview` PERF line in the log.
  private func readPreviewCount(from url: URL) -> Int {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      if let text = try? String(contentsOf: url, encoding: .utf8),
         let line = text.split(separator: "\n").first(where: { $0.contains("op=preview") }),
         let itemsField = line.split(separator: "|").first(where: { $0.contains("items=") }),
         let value = itemsField.split(separator: "=").last {
        return Int(value) ?? 0
      }
      usleep(200_000)
    }
    return 0
  }
}
