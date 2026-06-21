import AppKit
import CoreGraphics
import XCTest

/// Regression test for the preview-stale bug: before the fix, `AsyncView` used
/// a plain `.task` (no id) and `PreviewItemView` kept structural identity across
/// selection changes, so navigating down the list did NOT re-run
/// `asyncGetPreviewImage` — the preview showed the first item's image stuck.
///
/// With the fix (`AsyncView(id:)` keyed on `item.id`), each selection change
/// cancels and restarts the task, so the preview re-renders per item. This test
/// drives the real popup + preview pane through several down-arrows and asserts
/// the in-app `PerfRecorder` recorded more than one preview render — i.e. the
/// preview actually refreshed across navigation (not stuck on item 0).
///
/// Uses the `MaccyPerfRecord` instrumentation bridge (same as the B benchmarks).
/// Non-blocking context (perf shards, continue-on-error): a flake must never
/// fail the gate, so the assertion is best-effort.
final class PreviewRefreshUITests: XCTestCase {
  private let app = XCUIApplication()
  private let pasteboard = NSPasteboard.general
  private var perfLogURL: URL = URL(fileURLWithPath: "/dev/null")

  private static let perfReset = "org.p0deje.Maccy.Perf.reset"
  private static let perfDump = "org.p0deje.Maccy.Perf.dump"
  private static let perfOpenPreview = "org.p0deje.Maccy.Perf.openPreview"

  override func setUp() {
    super.setUp()
    perfLogURL = URL.temporaryDirectory
      .appendingPathComponent("maccy-preview-\(UUID().uuidString).log")
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

  func testPreviewRefreshesAcrossNavigation() throws {
    // Populate several distinct image items via the real pasteboard.
    for seed in 1...8 {
      copyToClipboard(makeImage(seed: seed))
    }

    // Open popup, reset the cold-open render burst, open the preview pane.
    app.statusItems.firstMatch.click()
    if !app.staticTexts.firstMatch.waitForExistence(timeout: 5) {
      XCTFail("Maccy did not pop up")
    }
    usleep(500_000)
    post(Self.perfReset)
    post(Self.perfOpenPreview)
    // Let the first item's preview decode + render settle.
    usleep(1_500_000)

    // Navigate down 2 distinct items, slowly enough that each preview's
    // off-main decode completes (small images decode fast, but the headless
    // runner is heavily contended — leave generous margin). Before the fix,
    // only the first item's preview ever generated (the view never re-
    // requested); after the fix, each selection generates a new preview.
    for _ in 0..<2 {
      app.typeKey(.downArrow, modifierFlags: [])
      usleep(1_200_000)
    }
    usleep(2_000_000) // let the final off-main decode publish.

    post(Self.perfDump, userInfo: ["category": "preview-refresh"])
    usleep(500_000)

    // Diagnostic: print the raw dump so CI shows what (if anything) the app
    // recorded. Removed once the preview-refresh path is confirmed stable.
    printRawDump(from: perfLogURL)
    let previewCount = readPreviewCount(from: perfLogURL)
    // Before the fix this was 0–1 (the stuck first render). After the fix,
    // navigating 3 items must produce multiple preview renders.
    XCTAssertGreaterThan(
      previewCount,
      1,
      "Preview did not refresh across navigation (preview renders = \(previewCount)); "
        + "the preview-stale bug may have regressed."
    )
  }

  // MARK: - Helpers

  private func copyToClipboard(_ content: NSImage) {
    pasteboard.clearContents()
    pasteboard.setData(content.tiffRepresentation, forType: .tiff)
    usleep(1_500_000) // clipboard check interval is ~1s
  }

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

  /// Prints the raw dump file contents (diagnostic).
  private func printRawDump(from url: URL) {
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? "<unreadable>"
    print("PERFRAW|file=\(url.lastPathComponent)|content=\(text)")
  }

  private func makeImage(seed: Int) -> NSImage {
    let width = 800
    let height = 600
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return NSImage()
    }
    let red = CGFloat((seed &* 37) % 256) / 255
    let green = CGFloat((seed &* 53) % 256) / 255
    let blue = CGFloat((seed &* 71) % 256) / 255
    context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    var state = UInt64(seed * seed + 7)
    for _ in 0..<300 {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      let xPos = CGFloat((state >> 33) % UInt64(width))
      let yPos = CGFloat((state >> 11) % UInt64(height))
      let dimension = CGFloat((state >> 50) % 80) + 5
      let channel = CGFloat((state >> 20) % 256) / 255
      context.setFillColor(red: channel, green: 1 - channel, blue: 0.5, alpha: 0.6)
      context.fill(CGRect(x: xPos, y: yPos, width: dimension, height: dimension))
    }
    guard let cgImage = context.makeImage() else {
      return NSImage()
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
  }
}
