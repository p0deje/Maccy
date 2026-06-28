import Foundation
import os

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
final class MainThreadProbe: Sendable {
  private let interval: TimeInterval
  // Swift 6: all mutable state is held in a Sendable OSAllocatedUnfairLock (the
  // lock is `let` and Sendable; its State — a private struct of Sendable fields —
  // is Sendable). The class is therefore genuinely Sendable, no @unchecked.
  private struct State {
    var running = false
    var maxDelay: TimeInterval = 0
    var samplerThread: Thread?
  }
  private let state = OSAllocatedUnfairLock(initialState: State())

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
    state.withLock { $0.maxDelay }
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
  /// and `maxGap` stays 0.0 even after a real main block). And
  /// `RunLoop.main.run(until:)` is unavailable from async contexts (Swift 6
  /// error). So instead we enqueue a sentinel onto the main queue and await its
  /// completion via a continuation — the main run loop processes the queued
  /// sampler ticks (dispatched earlier, FIFO) before the sentinel, so by the
  /// time the sentinel runs all earlier ticks have recorded their delays. We
  /// repeat until `maxGap` stabilizes so a final late tick is not lost.
  func maxGapAsync() async -> TimeInterval {
    var previous = maxGap
    for _ in 0..<10 {
      await drainMainQueue()
      let current = maxGap
      if current <= previous {
        return current
      }
      previous = current
    }
    return maxGap
  }

  /// Awaits a sentinel block dispatched to the main queue. Because the main
  /// queue is FIFO, all sampler ticks dispatched before the sentinel are
  /// processed first — so after this returns, those ticks' delays are recorded
  /// in `maxGap`. Async-safe (no `RunLoop.main.run`).
  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
  }

  func start() {
    stop()
    state.withLock { s in
      s.maxDelay = 0
      s.running = true
    }

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
    state.withLock { $0.samplerThread = thread }
  }

  func stop() {
    state.withLock { s in
      s.running = false
      s.samplerThread = nil
    }
  }

  /// Resets `maxGap` to zero without restarting the sampler — for per-item
  /// measurements within one probe session.
  func reset() {
    state.withLock { $0.maxDelay = 0 }
  }

  // MARK: - Private (called from arbitrary threads)

  private var isRunning: Bool {
    state.withLock { $0.running }
  }

  private var samplingInterval: TimeInterval { interval }

  /// Runs on the main thread (via `DispatchQueue.main.async`). The delay between
  /// `dispatchedAt` (background) and `processedAt` (main) is the time main left
  /// this tick waiting = main's unavailability at the dispatch instant.
  private func recordMainTick(dispatchedAt: Date) {
    let processedAt = Date()
    let delay = processedAt.timeIntervalSince(dispatchedAt)
    state.withLock { s in
      if delay > s.maxDelay {
        s.maxDelay = delay
      }
    }
  }
}
