import AppKit
import Defaults

// swiftlint:disable identifier_name
// swiftlint:disable type_name
class Sorter {
  enum By: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
    case lastCopiedAt
    case lastCopiedAtReversed
    case firstCopiedAt
    case numberOfCopies

    var id: Self { self }

    var description: String {
      switch self {
      case .lastCopiedAt:
        return NSLocalizedString("LastCopiedAt", tableName: "StorageSettings", comment: "")
      case .lastCopiedAtReversed:
        return NSLocalizedString("LastCopiedAtReversed", tableName: "StorageSettings", comment: "")
      case .firstCopiedAt:
        return NSLocalizedString("FirstCopiedAt", tableName: "StorageSettings", comment: "")
      case .numberOfCopies:
        return NSLocalizedString("NumberOfCopies", tableName: "StorageSettings", comment: "")
      }
    }
  }

  func sort(_ items: [HistoryItem], by: By = Defaults[.sortBy]) -> [HistoryItem] {
    return items
      .sorted(by: { return bySortingAlgorithm($0, $1, by) })
      .sorted(by: byPinned)
  }

    private func bySortingAlgorithm(_ lhs: HistoryItem, _ rhs: HistoryItem, _ by: By) -> Bool {
      switch by {
      case .firstCopiedAt:
        return lhs.firstCopiedAt > rhs.firstCopiedAt
      case .numberOfCopies:
        return lhs.numberOfCopies > rhs.numberOfCopies
      case .lastCopiedAtReversed:
        // 1️⃣ Never-used items first
        if lhs.lastUsedAt == nil && rhs.lastUsedAt != nil {
          return true
        }
        if lhs.lastUsedAt != nil && rhs.lastUsedAt == nil {
          return false
        }
        // 2️⃣ Both never used → FIFO by copy time
        if lhs.lastUsedAt == nil && rhs.lastUsedAt == nil {
          if lhs.lastCopiedAt != rhs.lastCopiedAt {
            return lhs.lastCopiedAt < rhs.lastCopiedAt
          }
          // tie-breaker (guarantees total order)
          return lhs.firstCopiedAt < rhs.firstCopiedAt
        }
        // 3️⃣ Both used → FIFO by usage time
        if lhs.lastUsedAt! != rhs.lastUsedAt! {
          return lhs.lastUsedAt! < rhs.lastUsedAt!
        }
        // Final tie-breaker (required)
        return lhs.lastCopiedAt < rhs.lastCopiedAt

      case .lastCopiedAt:
        return lhs.lastCopiedAt > rhs.lastCopiedAt
      // default:
        // return lhs.lastCopiedAt > rhs.lastCopiedAt
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
// swiftlint:enable type_name
