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
    let sortedUnpinned = items
      .filter { $0.pin == nil }
      .sorted(by: { bySortingAlgorithm($0, $1, by) })

    let pinnedItems = items.filter { $0.pin != nil }
    let pinOrder = Defaults[.pinOrder].pins

    var pinnedByPin: [String: HistoryItem] = [:]
    for item in pinnedItems {
      if let pin = item.pin {
        pinnedByPin[pin] = item
      }
    }

    var orderedPinned: [HistoryItem] = pinOrder.compactMap { pinnedByPin[$0] }
    let orderedPinSet = Set(pinOrder)
    orderedPinned += pinnedItems.filter {
      guard let pin = $0.pin else { return false }
      return !orderedPinSet.contains(pin)
    }

    switch Defaults[.pinTo] {
    case .top:
      return orderedPinned + sortedUnpinned
    case .bottom:
      return sortedUnpinned + orderedPinned
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

}
// swiftlint:enable identifier_name
// swiftlint:enable type_name
