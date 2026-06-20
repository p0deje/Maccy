import XCTest

/// Confirms the perf path is wired: a perf class registers in MaccyTests and
/// runs in the perf CI step. Trivial `measure{}`; replaced by real benchmarks
/// in later tasks. No `@testable import Maccy` — references no Maccy types.
final class PerformanceHarnessWiringTest: XCTestCase {
  func testWiringRunsAndMeasures() {
    measure {
      _ = (0..<1000).reduce(0, +)
    }
  }
}
