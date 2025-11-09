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
    let byAlgorithm = items.sorted(by: { return bySortingAlgorithm($0, $1, by) })

    let pinned = byAlgorithm.filter { $0.pin != nil }
    let unpinned = byAlgorithm.filter { $0.pin == nil }

    // Respect user-defined pinned order if present
    let order = Defaults[.pinnedOrder]
    let orderedPinned: [HistoryItem]
    if order.isEmpty {
      orderedPinned = pinned
    } else {
      var result: [HistoryItem] = []
      // First, pins that are in the order list
      for key in order {
        if let item = pinned.first(where: { $0.pin == key }) {
          result.append(item)
        }
      }
      // Then, any remaining pins (e.g., new ones) keeping their algorithm order
      for item in pinned where !order.contains(item.pin ?? "") {
        result.append(item)
      }
      orderedPinned = result
    }

    if Defaults[.pinTo] == .bottom {
      return unpinned + orderedPinned
    } else {
      return orderedPinned + unpinned
    }
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
    if Defaults[.pinTo] == .bottom {
      return (lhs.pin == nil) && (rhs.pin != nil)
    } else {
      return (lhs.pin != nil) && (rhs.pin == nil)
    }
  }
}
// swiftlint:enable identifier_name
// swiftlint:enable type_name
