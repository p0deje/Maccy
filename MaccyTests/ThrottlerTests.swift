import XCTest
@testable import Maccy

final class ThrottlerTests: XCTestCase {
  // The very first invocation (no previous run) must execute immediately,
  // not be delayed by the full minimumDelay.
  func testFirstInvocationFiresImmediately() {
    let minimumDelay: TimeInterval = 0.3
    let throttler = Throttler(minimumDelay: minimumDelay)
    let fired = expectation(description: "First invocation fires immediately")

    throttler.throttle { fired.fulfill() }

    // If the first call were (incorrectly) delayed by minimumDelay, the block
    // would only run after 0.3s and this shorter wait would time out.
    wait(for: [fired], timeout: minimumDelay / 2)
  }

  // A call made within minimumDelay of the previous run must be deferred.
  func testSubsequentInvocationWithinMinimumDelayIsDeferred() {
    let minimumDelay: TimeInterval = 0.3
    let throttler = Throttler(minimumDelay: minimumDelay)

    // First call fires immediately and records the previous run time.
    let firstFired = expectation(description: "First invocation fires")
    throttler.throttle { firstFired.fulfill() }
    wait(for: [firstFired], timeout: minimumDelay * 2)

    // A second call right away is within minimumDelay, so it must be deferred.
    let secondFired = expectation(description: "Second invocation fires after delay")
    let startedAt = Date()
    throttler.throttle {
      XCTAssertGreaterThanOrEqual(
        Date().timeIntervalSince(startedAt),
        minimumDelay * 0.9,
        "Call within minimumDelay should be deferred by ~minimumDelay"
      )
      secondFired.fulfill()
    }
    wait(for: [secondFired], timeout: minimumDelay * 4)
  }

  // Once enough time has elapsed since the previous run, the next call must fire
  // immediately again — the repeat-caller immediate path, which compares against
  // a real previousRun rather than Date.distantPast.
  func testInvocationAfterMinimumDelayFiresImmediately() {
    let minimumDelay: TimeInterval = 0.3
    let throttler = Throttler(minimumDelay: minimumDelay)

    // First call fires immediately and records the previous run time.
    let firstFired = expectation(description: "First invocation fires")
    throttler.throttle { firstFired.fulfill() }
    wait(for: [firstFired], timeout: minimumDelay * 2)

    // Wait past minimumDelay so the elapsed-since-last-run exceeds it.
    let elapsed = expectation(description: "Waited past minimumDelay")
    DispatchQueue.main.asyncAfter(deadline: .now() + minimumDelay + 0.1) { elapsed.fulfill() }
    wait(for: [elapsed], timeout: minimumDelay * 4)

    // A new call should now fire immediately. If the elapsed comparison were
    // (incorrectly) evaluated backwards, this call would be delayed by the full
    // minimumDelay and this shorter wait would time out.
    let refired = expectation(description: "Invocation after delay fires immediately")
    throttler.throttle { refired.fulfill() }
    wait(for: [refired], timeout: minimumDelay / 2)
  }
}
