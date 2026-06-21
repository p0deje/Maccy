import Foundation

/// Probes the main thread's responsiveness by sampling from a background
/// thread: every `interval` seconds it records the dispatch time, then dispatches
/// a tick to the main queue; when main processes the tick it measures the delay
/// (`processedAt - dispatchedAt`) — i.e. how long that one tick waited for main.
/// `maxGap` is the worst such delay seen since `start()` / last `reset()`.
///
/// The per-tick **delay** metric (not the inter-tick gap) is what matters: it's
/// the actual time main left a tick waiting, so it reflects real main-thread
/// unavailability and is robust to the background thread's own scheduling jitter
/// (a slow-to-wake sampler dispatches fewer ticks but each tick's delay still
/// measures main's responsiveness at its dispatch instant). Deliberately NOT
/// `Timer.scheduledTimer` (run-loop-mode-bound, never fires in async tests) and
/// NOT an inter-tick gap (conflates sampler cadence with main blocking).
///
/// Note: the ticks are processed on main, so a measurement only sees the delay
/// once main has run the tick — callers must `await` (yield) before reading
/// `maxGap` so queued ticks get processed.
final class MainThreadProbe {
  private let interval: TimeInterval
  private let lock = NSLock()
  private var running = false
  private var maxDelayValue: TimeInterval = 0
  private var samplerThread: Thread?

  init(interval: TimeInterval = 0.005) {
    self.interval = interval
  }

  /// Worst main-thread processing delay observed since `start()` / last
  /// `reset()`, in seconds (how long the slowest dispatched tick waited for main).
  ///
  /// IMPORTANT: only valid after the caller has yielded to the main run loop
  /// (e.g. via `await maxGapAsync()` or an `await` in the calling async test).
  /// The sampler dispatches ticks via `DispatchQueue.main.async`; those ticks
  /// only run — and only then update `maxDelayValue` — when main is free. A
  /// synchronous read immediately after a main-blocking region returns 0.0
  /// because the queued ticks have not been processed yet. Prefer
  /// `maxGapAsync()`.
  var maxGap: TimeInterval {
    lock.lock()
    defer { lock.unlock() }
    return maxDelayValue
  }

  /// Drains queued sampler ticks then returns `maxGap`. This is the correct way
  /// to read the probe from an async test: it guarantees the ticks dispatched
  /// during the measured region have been processed on main and their delays
  /// recorded.
  ///
  /// IMPORTANT subtlety: the sampler dispatches ticks via
  /// `DispatchQueue.main.async`, which are processed by the **main run loop** —
  /// NOT by `await Task.yield()` (yielding only suspends the current cooperative
  /// task; it does not pump the run loop, so dispatched main closures don't run
  /// and `maxGap` stays 0.0 even after a real main block). So this pumps the main
  /// run loop explicitly via `RunLoop.main.run(until:)`, repeating until `maxGap`
  /// stabilizes (no increase across a pump) or a small cap is hit, so a final
  /// late tick is not lost.
  func maxGapAsync() async -> TimeInterval {
    var previous = maxGap
    for _ in 0..<10 {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
      let current = maxGap
      if current <= previous {
        return current
      }
      previous = current
    }
    return maxGap
  }

  func start() {
    stop()
    lock.lock()
    maxDelayValue = 0
    running = true
    lock.unlock()

    let probe = self
    let thread = Thread {
      while probe.isRunning {
        Thread.sleep(forTimeInterval: probe.samplingInterval)
        let dispatchedAt = Date()
        DispatchQueue.main.async {
          probe.recordMainTick(dispatchedAt: dispatchedAt)
        }
      }
    }
    thread.name = "MainThreadProbe.sampler"
    thread.start()
    samplerThread = thread
  }

  func stop() {
    lock.lock()
    running = false
    lock.unlock()
    samplerThread = nil
  }

  /// Resets `maxGap` to zero without restarting the sampler — for per-item
  /// measurements within one probe session.
  func reset() {
    lock.lock()
    maxDelayValue = 0
    lock.unlock()
  }

  // MARK: - Private (called from arbitrary threads)

  private var isRunning: Bool {
    lock.lock()
    defer { lock.unlock() }
    return running
  }

  private var samplingInterval: TimeInterval { interval }

  /// Runs on the main thread (via `DispatchQueue.main.async`). The delay between
  /// `dispatchedAt` (background) and `processedAt` (main) is the time main left
  /// this tick waiting = main's unavailability at the dispatch instant.
  private func recordMainTick(dispatchedAt: Date) {
    let processedAt = Date()
    let delay = processedAt.timeIntervalSince(dispatchedAt)
    lock.lock()
    if delay > maxDelayValue {
      maxDelayValue = delay
    }
    lock.unlock()
  }
}
