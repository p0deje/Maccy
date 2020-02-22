import AppKit

public struct HistoryItem: Equatable, Codable {
  public let value: String

  public static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
    return lhs.value == rhs.value
  }

  init(value: String) {
    self.value = value
  }
}
