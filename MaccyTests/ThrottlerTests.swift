import Foundation
import Testing
@testable import Maccy

@MainActor
struct ThrottlerTests {
  // Check queue ordering rather than exact elapsed times. The checkpoint is
  // scheduled before the request, halfway through the minimum delay.
  private func runsBeforeCheckpoint(_ throttler: Throttler) async -> Bool {
    await withCheckedContinuation { continuation in
      var ran = false
      DispatchQueue.main.asyncAfter(deadline: .now() + throttler.minimumDelay / 2) {
        continuation.resume(returning: ran)
      }
      throttler.throttle { ran = true }
    }
  }

  private func wait(_ interval: TimeInterval) async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
        continuation.resume()
      }
    }
  }

  private func run(_ throttler: Throttler) async {
    await withCheckedContinuation { continuation in
      throttler.throttle { continuation.resume() }
    }
  }

  @Test("First call does not wait for the minimum delay")
  func firstCall() async {
    let throttler = Throttler(minimumDelay: 0.2)
    #expect(await runsBeforeCheckpoint(throttler))
    throttler.cancel()
  }

  @Test("Call after idle does not wait for the minimum delay")
  func callAfterIdle() async {
    let throttler = Throttler(minimumDelay: 0.2)
    await run(throttler)
    await wait(0.3)
    #expect(await runsBeforeCheckpoint(throttler))
    throttler.cancel()
  }

  @Test("Recent calls retain the delay and only the latest callback runs")
  func recentCalls() async {
    let throttler = Throttler(minimumDelay: 0.2)
    await run(throttler)
    var callbacks: [Int] = []
    let earlyCallbacks: [Int] = await withCheckedContinuation { continuation in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        continuation.resume(returning: callbacks)
      }
      throttler.throttle { callbacks.append(1) }
      throttler.throttle { callbacks.append(2) }
      throttler.throttle { callbacks.append(3) }
    }
    #expect(earlyCallbacks.isEmpty)
    await wait(0.3)
    #expect(callbacks == [3])
  }

  @Test("Cancel prevents a pending callback from running")
  func cancelPendingCall() async {
    let throttler = Throttler(minimumDelay: 0.2)
    await run(throttler)
    var ran = false
    throttler.throttle { ran = true }
    throttler.cancel()
    await wait(0.3)
    #expect(!ran)
  }
}
