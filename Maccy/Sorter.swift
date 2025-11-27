import AppKit
import Defaults

// swiftlint:disable identifier_name
// swiftlint:disable type_name
class Sorter {
  enum By: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
    case lastCopiedAt
    case firstCopiedAt
    case numberOfCopies
    case pinShortcutKey

    var id: Self { self }

    var description: String {
      switch self {
      case .lastCopiedAt:
        return NSLocalizedString("LastCopiedAt", tableName: "StorageSettings", comment: "")
      case .firstCopiedAt:
        return NSLocalizedString("FirstCopiedAt", tableName: "StorageSettings", comment: "")
      case .numberOfCopies:
        return NSLocalizedString("NumberOfCopies", tableName: "StorageSettings", comment: "")
      case .pinShortcutKey:
        return NSLocalizedString("PinShortcutKey", tableName: "StorageSettings", comment: "")
      }
    }
  }

  func sort(_ items: [HistoryItem], by: By = Defaults[.sortBy]) -> [HistoryItem] {
    return items
      .sorted(by: { return bySortingAlgorithm($0, $1, by) })
      .sorted(by: byPinned)
  }

  private func bySortingAlgorithm(_ lhs: HistoryItem, _ rhs: HistoryItem, _ by: By) -> Bool {
    let order = Defaults[.sortOrder]
    let result: Bool

    switch by {
    case .firstCopiedAt:
      result = lhs.firstCopiedAt < rhs.firstCopiedAt
    case .numberOfCopies:
      result = lhs.numberOfCopies < rhs.numberOfCopies
    case .pinShortcutKey:
      result = (lhs.pin ?? "").localizedCaseInsensitiveCompare(rhs.pin ?? "") == .orderedAscending
    default:
      result = lhs.lastCopiedAt < rhs.lastCopiedAt
    }
    return order ? result : !result
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
