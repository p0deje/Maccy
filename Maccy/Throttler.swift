import Foundation

/// Coalesces rapid calls into at most one execution per `minimumDelay` window.
///
/// Based on https://www.craftappco.com/blog/2018/5/30/simple-throttling-in-swift.
class Throttler {
  var minimumDelay: TimeInterval

  private var workItem: DispatchWorkItem = DispatchWorkItem(block: {})
  private var previousRun: Date = Date.distantPast
  private let queue: DispatchQueue

  init(minimumDelay: TimeInterval, queue: DispatchQueue = DispatchQueue.main) {
    self.minimumDelay = minimumDelay
    self.queue = queue
  }

  /// Schedules `block`, executing immediately if enough time has passed since
  /// the last run, otherwise delaying by `minimumDelay`.
  func throttle(_ block: @escaping () -> Void) {
    cancel()

    workItem = DispatchWorkItem { [weak self] in
      self?.previousRun = Date()
      block()
    }

    let delay = -previousRun.timeIntervalSinceNow > minimumDelay ? 0 : minimumDelay
    queue.asyncAfter(deadline: .now() + Double(delay), execute: workItem)
  }

  /// Cancels the pending throttled execution, if any.
  func cancel() {
    workItem.cancel()
  }
}
