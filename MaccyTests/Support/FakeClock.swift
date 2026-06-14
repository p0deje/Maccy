import Foundation

struct FakeClock: Sendable {
  private(set) var now: Date

  init(now: Date = Date(timeIntervalSince1970: 1_717_171_717)) {
    self.now = now
  }

  mutating func advance(by interval: TimeInterval) {
    now = now.addingTimeInterval(interval)
  }

  var nowProvider: @Sendable () -> Date {
    { now }
  }
}
