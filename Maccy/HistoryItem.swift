import AppKit

public class HistoryItem: Equatable, Codable {
  public let value: String
  public var firstCopiedAt: Date!
  public var lastCopiedAt: Date!
  public var numberOfCopies: Int!
  public var pin: String?

  public static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
    return lhs.value == rhs.value
  }

  init(value: String) {
    self.value = value
    self.firstCopiedAt = Date()
    self.lastCopiedAt = firstCopiedAt
    self.numberOfCopies = 1
  }

  init(value: String, firstCopiedAt: Date, lastCopiedAt: Date, numberOfCopies: Int) {
    self.value = value
    self.firstCopiedAt = firstCopiedAt
    self.lastCopiedAt = lastCopiedAt
    self.numberOfCopies = numberOfCopies
  }
}
