import AppKit
import Defaults

// swiftlint:disable identifier_name
// swiftlint:disable type_name
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
    default:
      return lhs.lastCopiedAt > rhs.lastCopiedAt
    }
  }

  private func byPinned(_ lhs: HistoryItem, _ rhs: HistoryItem) -> Bool {
    // If one is pinned and the other is not, ensure pinned items are placed
    // according to `pinTo` setting. If both are pinned, preserve the
    // custom `pinOrder` value so user-arranged order is kept.
    let lhsPinned = lhs.pin != nil
    let rhsPinned = rhs.pin != nil

    if lhsPinned && !rhsPinned {
      return Defaults[.pinTo] == .top
    }

    if !lhsPinned && rhsPinned {
      return Defaults[.pinTo] != .top
    }

    // Both pinned or both unpinned — when both pinned prefer `pinOrder`.
    if lhsPinned && rhsPinned {
      return lhs.pinOrder < rhs.pinOrder
    }

    // Neither pinned — keep original order by returning false so other
    // sort criteria decide.
    return false
  }
}
// swiftlint:enable identifier_name
// swiftlint:enable type_name
