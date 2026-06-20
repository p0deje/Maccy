import Foundation

/// Probes the main thread's responsiveness by sampling from a background
/// thread: every `interval` seconds it dispatches a tick to the main queue and
/// measures how long that tick waits before main processes it. If main is
/// blocked, the queued tick is delayed and the inter-tick gap grows; `maxGap`
/// is the worst stall seen since `start()` / last `reset()`.
///
/// Background-thread + `DispatchQueue.main.async` based — deliberately NOT
/// `Timer.scheduledTimer`, which only fires in the main run loop's current mode
/// and silently never ticks in async `@MainActor` tests (leaving `maxGap` stuck
/// at 0). This sampler is run-loop-mode-independent, so it works in XCTest
/// async contexts. `maxGap` includes the `interval` baseline (a free main thread
/// reads ~`interval`); subtract it for the true stall.
final class MainThreadProbe {
  private let interval: TimeInterval
  private let lock = NSLock()
  private var running = false
  private var lastMainTick: Date = .distantPast
  private var maxGapValue: TimeInterval = 0
  private var samplerThread: Thread?

  init(interval: TimeInterval = 0.005) {
    self.interval = interval
  }

  /// Worst main-thread stall observed since `start()` / last `reset()`, seconds.
  var maxGap: TimeInterval {
    lock.lock()
    defer { lock.unlock() }
    return maxGapValue
  }

  func start() {
    stop()
    lock.lock()
    maxGapValue = 0
    lastMainTick = Date()
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

  /// Resets `maxGap` to zero (and the tick baseline to now) without restarting
  /// the sampler — for per-item measurements within one probe session.
  func reset() {
    lock.lock()
    maxGapValue = 0
    lastMainTick = Date()
    lock.unlock()
  }

  // MARK: - Private (called from arbitrary threads)

  private var isRunning: Bool {
    lock.lock()
    defer { lock.unlock() }
    return running
  }

  private var samplingInterval: TimeInterval { interval }

  /// Runs on the main thread (via `DispatchQueue.main.async`).
  private func recordMainTick(dispatchedAt: Date) {
    let processedAt = Date()
    lock.lock()
    let gap = processedAt.timeIntervalSince(lastMainTick)
    lastMainTick = processedAt
    if gap > maxGapValue {
      maxGapValue = gap
    }
    lock.unlock()
  }
}
