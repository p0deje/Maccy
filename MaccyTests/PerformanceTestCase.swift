import Defaults
import XCTest
@testable import Maccy

/// Base class for performance tests. `enable-testing` (the test plan's default
/// launch argument) forces an in-memory SwiftData store, so each test gets a
/// fresh `History.shared`. Sets `Defaults[.size]` high enough that the requested
/// item count is not trimmed, and restores the saved value in `tearDown`.
@MainActor
class PerformanceTestCase: XCTestCase {
  private let savedSize = Defaults[.size]
  /// Fixture corpus directory. When `MACCY_PERF_FIXTURES` is set (CI pre-seeds a
  /// shared corpus there), it is reused across tests and runs; otherwise a fresh
  /// per-run temp directory is generated each run.
  let cacheDir: URL = {
    if let shared = ProcessInfo.processInfo.environment["MACCY_PERF_FIXTURES"] {
      return URL(fileURLWithPath: shared)
    }
    return FileManager.default.temporaryDirectory
      .appending(path: "MaccyPerf-\(UUID().uuidString)")
  }()
  let probe = MainThreadProbe(interval: 0.01)

  override func setUp() async throws {
    try await super.setUp()
    History.shared.clearAll()
    History.shared.searchQuery = ""
    // Allow up to 200 items (the real default cap) without trimming.
    Defaults[.size] = 200
  }

  override func tearDown() async throws {
    probe.stop()
    History.shared.clearAll()
    History.shared.searchQuery = ""
    Defaults[.size] = savedSize
    // Only clean up a per-run temp corpus dir; never the shared
    // MACCY_PERF_FIXTURES dir (it persists across runs/tests).
    if ProcessInfo.processInfo.environment["MACCY_PERF_FIXTURES"] == nil {
      try? FileManager.default.removeItem(at: cacheDir)
    }
    try await super.tearDown()
  }

  /// Asserts no main-thread stall exceeded `threshold` since `probe.start()`.
  /// The default 16 ms equals one display frame, the budget the main thread must
  /// stay within for jank-free interaction.
  ///
  /// This method is `async` because it must drain the probe's queued sampler
  /// ticks — they only record their delay once the main thread runs them —
  /// before reading `maxGap`. A synchronous read returns `0.0` because the ticks
  /// have not yet been delivered.
  func assertMainThreadFree(threshold: TimeInterval = 0.016,
                            file: StaticString = #filePath, line: UInt = #line) async {
    let gap = await probe.maxGapAsync()
    XCTAssertLessThan(
      gap,
      threshold,
      "Main thread stalled \(gap)s > \(threshold)s threshold",
      file: file,
      line: line
    )
  }
}
