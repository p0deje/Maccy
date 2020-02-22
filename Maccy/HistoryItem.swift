import AppKit

public class HistoryItem: Equatable, Codable {
  public let value: String
  public var firstCopiedAt: Date!
  public var lastCopiedAt: Date!

  public static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
    return lhs.value == rhs.value
  }

  init(value: String) {
    self.value = value
    self.firstCopiedAt = Date()
    self.lastCopiedAt = firstCopiedAt
  }

  init(value: String, firstCopiedAt: Date, lastCopiedAt: Date) {
    self.value = value
    self.firstCopiedAt = firstCopiedAt
    self.lastCopiedAt = lastCopiedAt
  }
}
