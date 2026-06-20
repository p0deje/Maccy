import Defaults
import XCTest
@testable import Maccy

/// Base for performance tests. `enable-testing` (the test plan's default launch
/// argument) forces an in-memory SwiftData store, so each test gets a fresh
/// `History.shared`. Sets `Defaults[.size]` high enough that the requested N is
/// not trimmed by `limitHistorySize`, and restores it in tearDown.
@MainActor
class PerformanceTestCase: XCTestCase {
  private let savedSize = Defaults[.size]
  let cacheDir: URL = FileManager.default.temporaryDirectory
    .appending(path: "MaccyPerf-\(UUID().uuidString)")
  let probe = MainThreadProbe(interval: 0.01)

  override func setUp() {
    super.setUp()
    History.shared.clearAll()
    History.shared.searchQuery = ""
    // Allow up to 200 items (the real default cap) without trimming.
    Defaults[.size] = 200
  }

  override func tearDown() {
    probe.stop()
    History.shared.clearAll()
    History.shared.searchQuery = ""
    Defaults[.size] = savedSize
    try? FileManager.default.removeItem(at: cacheDir)
    super.tearDown()
  }

  /// Asserts no main-thread stall exceeded `threshold` since `probe.start()`.
  /// Default 16 ms = one frame; the roadmap's gates require the main thread to
  /// stay free of >16 ms synchronous heavy work.
  func assertMainThreadFree(threshold: TimeInterval = 0.016,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThan(
      probe.maxGap,
      threshold,
      "Main thread stalled \(probe.maxGap)s > \(threshold)s threshold",
      file: file,
      line: line
    )
  }
}
