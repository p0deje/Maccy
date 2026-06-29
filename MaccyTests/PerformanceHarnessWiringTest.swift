import XCTest

/// Confirms the performance test harness is wired: a perf class registers in
/// `MaccyTests` and runs in the performance CI step. It exercises only a trivial
/// `measure{}` block — real benchmarks live in dedicated perf test classes.
final class PerformanceHarnessWiringTest: XCTestCase {
  func testWiringRunsAndMeasures() {
    measure {
      _ = (0..<1000).reduce(0, +)
    }
  }
}
