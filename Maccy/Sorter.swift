import AppKit
import Defaults

// swiftlint:disable identifier_name
class Sorter {
  enum By: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
    case lastCopiedAt
    case firstCopiedAt
    case numberOfCopies

    var id: Self { self }

    var description: String {
      switch self {
      case .lastCopiedAt:
        return NSLocalizedString("LastCopiedAt", tableName: "StorageSettings", comment: "")
      case .firstCopiedAt:
        return NSLocalizedString("FirstCopiedAt", tableName: "StorageSettings", comment: "")
      case .numberOfCopies:
        return NSLocalizedString("NumberOfCopies", tableName: "StorageSettings", comment: "")
      }
    }
  }

  private var by: By

  init(by: By) {
    self.by = by
  }

  func sort(_ items: [HistoryItem]) -> [HistoryItem] {
    return items.sorted(by: bySortingAlgorithm(_:_:)).sorted(by: byPinned(_:_:))
  }

  private func bySortingAlgorithm(_ lhs: HistoryItem, _ rhs: HistoryItem) -> Bool {
    switch by {
    case .firstCopiedAt:
      return lhs.firstCopiedAt > rhs.firstCopiedAt
    case .numberOfCopies:
      return lhs.numberOfCopies > rhs.numberOfCopies
    default:
      return lhs.lastCopiedAt > rhs.lastCopiedAt
    }
  }

  private func byPinned(_ lhs: HistoryItem, _ rhs: HistoryItem) -> Bool {
    if Defaults[.pinTo] == .bottom {
      return (lhs.pin == nil) && (rhs.pin != nil)
    } else {
      return (lhs.pin != nil) && (rhs.pin == nil)
    }
  }
}
// swiftlint:enable identifier_name
