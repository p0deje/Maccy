import Foundation

@MainActor
final class MainThreadProbe {
  private let interval: TimeInterval
  private var timer: Timer?
  private var lastTick: Date?
  private(set) var maxGap: TimeInterval = 0

  init(interval: TimeInterval = 0.01) {
    self.interval = interval
  }

  func start() {
    stop()
    lastTick = Date()
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.tick()
      }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    lastTick = nil
  }

  private func tick() {
    let now = Date()
    if let lastTick {
      maxGap = max(maxGap, now.timeIntervalSince(lastTick))
    }
    lastTick = now
  }
}
