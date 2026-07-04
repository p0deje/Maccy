import AsyncAlgorithms
import XCTest
@testable import Maccy

/// Build-integration gate for the `swift-async-algorithms` dependency.
///
/// The search-dispatch migration (T1.0b, ADR-7) relies on
/// `AsyncSequence.debounce(for:)` — Apple's official, stable rate-limiting
/// primitive (`throttle` was removed from the public surface in 1.0.4, but
/// `debounce` is stable and is exactly the quiescence semantic Maccy's
/// per-keystroke search needs). This test pins that the package resolves and
/// `debounce` is callable from this target, so a malformed SPM wiring — or a
/// future package bump that removed/renamed the public `debounce` API — fails
/// here, in isolation, rather than in the `History` migration.
final class AsyncAlgorithmsIntegrationTests: XCTestCase {
  /// An already-finished stream debounces to nothing — deterministic and
  /// timing-free (no quiescence window to wait out).
  func testDebounce_isCallableOnFinishedEmptyStream() async {
    let stream = AsyncStream<Int> { $0.finish() }
    let debounced = stream.debounce(for: .milliseconds(5))

    var count = 0
    for await _ in debounced { count += 1 }

    XCTAssertEqual(count, 0, "a finished stream that never yielded must produce no debounced values")
  }
}
