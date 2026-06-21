import AppKit
import CoreGraphics
import XCTest

/// `method=B` performance benchmarks: the same per-item render measurement
/// (thumbnail + preview, latency + main-thread block) as `method=A`
/// (`MaccyTests/ImageDecodePerformanceTests`), but driven through the **real
/// UI pipeline** — SwiftUI `.onAppear`/`AsyncView`, real `Task` scheduling,
/// `@Observable` propagation under selection traversal. A calls `ensure*()`
/// directly; B opens the popup, opens the preview pane, and arrow-keys down
/// through the first 20 items, exactly the "pointer moves onto each candidate
/// → render" path the user wants measured for blocking/latency.
///
/// Standalone (own minimal helpers) — does not subclass `MaccyUITests` and does
/// not edit it, to avoid perturbing the existing (flaky) suite. Runs in the
/// non-blocking perf shards (`continue-on-error`); a flake must never fail the
/// gate. Image fixtures are generated in-process via CoreGraphics (no binaries
/// committed, no images in logs — only `PERF|` text lines).
final class PerfRenderUITests: XCTestCase {
  private let app = XCUIApplication()
  private let pasteboard = NSPasteboard.general

  private var perfLogURL: URL = URL(fileURLWithPath: "/dev/null")

  // Population counts: large enough that 20 down-arrows scroll the list past
  // the fold (so `.onAppear` fires for newly-visible cells → thumbnail renders
  // during traversal, not just the popup-open cold burst).
  private let imageCount = 30
  private let textCount = 20
  private let mixedImageCount = 15
  private let mixedTextCount = 15

  override func setUp() {
    super.setUp()
    perfLogURL = URL.temporaryDirectory
      .appendingPathComponent("maccy-perf-\(UUID().uuidString).log")
    app.launchArguments += ["enable-testing", "MaccyPerfRecord"]
    app.launchEnvironment["MACCY_PERF_LOG"] = perfLogURL.path
    app.launch()
    assertStatusItemExists()
  }

  override func tearDown() {
    app.terminate()
    super.tearDown()
  }

  // MARK: - Scenarios

  /// Many images: visit the first 20 with the preview pane open. Thumbnail
  /// renders fire as cells scroll into view; preview renders fire as the lead
  /// selection moves.
  func testImageRenderB() throws {
    for seed in 1...imageCount {
      copyToClipboard(makeImage(seed: seed))
    }
    driveTraversal(category: "image", openPreview: true)
  }

  /// Many long texts: text items have no image data, so neither thumbnail nor
  /// preview image generation runs — the dump reports `items=0` for both ops,
  /// honestly confirming text traversal incurs no image-decode work (the
  /// image-vs-text contrast, matching A's "text all 0").
  func testTextRenderB() throws {
    for index in 1...textCount {
      copyToClipboard(makeLongText(index: index))
    }
    driveTraversal(category: "text", openPreview: false)
  }

  /// Many images + many long texts interleaved: visit the first 20. Image
  /// cells render (thumbnail on scroll, preview on selection); text cells do
  /// not. Tests the mixed-pipeline worst case.
  func testMixedRenderB() throws {
    for index in 1...mixedImageCount {
      copyToClipboard(makeImage(seed: index))
      copyToClipboard(makeLongText(index: index))
    }
    driveTraversal(category: "mixed", openPreview: true)
  }

  // MARK: - Traversal driver

  /// Opens the popup, resets the recorder (discards the cold-render burst),
  /// optionally opens the preview pane, arrow-keys down 20 times, then dumps
  /// and re-prints the `PERF|` lines from the log file.
  private func driveTraversal(category: String, openPreview: Bool) {
    popUpWithMouse()
    usleep(500_000)
    postPerfNotification(Self.perfReset)

    if openPreview {
      postPerfNotification(Self.perfOpenPreview)
      usleep(600_000)
    }

    for _ in 0..<20 {
      app.typeKey(.downArrow, modifierFlags: [])
      usleep(150_000)
    }
    // Let the final off-main decodes publish back to main.
    usleep(2_000_000)

    postPerfNotification(Self.perfDump, userInfo: ["category": category])
    usleep(500_000)
    printPerfLines(from: perfLogURL)
  }

  // MARK: - Clipboard / popup helpers (mirror MaccyUITests patterns)

  private func assertStatusItemExists() {
    if !app.statusItems.firstMatch.waitForExistence(timeout: 10) {
      XCTFail("Maccy status item did not appear")
    }
  }

  private func popUpWithMouse() {
    app.statusItems.firstMatch.click()
    if !app.staticTexts.firstMatch.waitForExistence(timeout: 5) {
      XCTFail("Maccy did not pop up")
    }
  }

  private func copyToClipboard(_ content: String) {
    pasteboard.clearContents()
    pasteboard.setString(content, forType: .string)
    waitTillClipboardCheck()
  }

  private func copyToClipboard(_ content: NSImage) {
    pasteboard.clearContents()
    pasteboard.setData(content.tiffRepresentation, forType: .tiff)
    waitTillClipboardCheck()
  }

  // Default clipboard check interval is 1s; 1.5s gives margin for the poll.
  private func waitTillClipboardCheck() {
    usleep(1_500_000)
  }

  // MARK: - Perf notification bridge

  private static let perfReset = "org.p0deje.Maccy.Perf.reset"
  private static let perfDump = "org.p0deje.Maccy.Perf.dump"
  private static let perfOpenPreview = "org.p0deje.Maccy.Perf.openPreview"

  private func postPerfNotification(_ name: String, userInfo: [String: Any]? = nil) {
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

  // MARK: - Fixture generation (in-process, deterministic, no binaries)

  /// A seed-dependent photo-like image (base fill + hundreds of varied rects)
  /// with high-frequency detail so it isn't trivially compressible — stresses
  /// the ImageIO decode path BS-3 moved off-main. Distinct per seed (distinct
  /// fingerprint → no `findSimilarItem` dedup). Returned as a CG-backed
  /// NSImage; the pasteboard carries its TIFF representation.
  private func makeImage(seed: Int) -> NSImage {
    let width = 1000
    let height = 750
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
    for _ in 0..<600 {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      let xValue = CGFloat((state >> 33) % UInt64(width))
      let yValue = CGFloat((state >> 11) % UInt64(height))
      let dimension = CGFloat((state >> 50) % 90) + 5
      let channel = CGFloat((state >> 20) % 256) / 255
      context.setFillColor(red: channel, green: 1 - channel, blue: 0.5, alpha: 0.6)
      context.fill(CGRect(x: xValue, y: yValue, width: dimension, height: dimension))
    }
    guard let cgImage = context.makeImage() else {
      return NSImage()
    }
    return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
  }

  /// A distinct long string (paragraph repeated + index suffix) so each text
  /// item has a unique value (no dedup) and a non-trivial title/preview.
  private func makeLongText(index: Int) -> String {
    let paragraph = "The quick brown fox jumps over the lazy dog. "
      + "Maccy is a lightweight clipboard manager for macOS. "
      + "This is a long-text fixture for the performance benchmark suite. "
    return String(repeating: paragraph, count: 60) + " #\(index)"
  }
}
