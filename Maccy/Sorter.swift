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

  enum PinBy: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
    case lastCopiedAt
    case firstCopiedAt
    case numberOfCopies
    case pinLetter
    case custom

    var id: Self { self }

    var description: String {
      if let by = By(rawValue: rawValue) {
        return by.description
      }

      switch self {
      case .pinLetter:
        return NSLocalizedString("PinLetter", tableName: "StorageSettings", comment: "")
      case .custom:
        return NSLocalizedString("Custom", tableName: "StorageSettings", comment: "")
      default:
        return rawValue
      }
    }
  }

  func sort(_ items: [HistoryItem], by: By = Defaults[.sortBy]) -> [HistoryItem] {
    let sortedUnpinned = items
      .filter { $0.pin == nil }
      .sorted(by: { bySortingAlgorithm($0, $1, by) })

    let pinnedItems = items.filter { $0.pin != nil }
    let sortedPinned = sortPins(pinnedItems, key: \.self)

    switch Defaults[.pinTo] {
    case .top:
      return sortedPinned + sortedUnpinned
    case .bottom:
      return sortedUnpinned + sortedPinned
    }
  }

  func sortPins(
    _ items: [HistoryItem],
    by: PinBy = Defaults[.pinSortBy]
  ) -> [HistoryItem] {
    return sortPins(items, key: \.self, by: by)
  }

  func sortPins<T>(
    _ items: [T],
    key: (T) -> HistoryItem,
    by: PinBy = Defaults[.pinSortBy]
  ) -> [T] {
    if let by = By(rawValue: by.rawValue) {
      return stableSort(items, key: key) { bySortingAlgorithm($0, $1, by) }
    }

    switch by {
    case .pinLetter:
      return stableSort(items, key: key) { ($0.pin ?? "") < ($1.pin ?? "") }
    case .custom:
      let indexes = Dictionary(
        uniqueKeysWithValues: Defaults[.pinOrder].pins.enumerated().map {
          ($0.element, $0.offset)
        }
      )
      return stableSort(items, key: key) {
        ($0.pin.flatMap { indexes[$0] } ?? Int.max)
          < ($1.pin.flatMap { indexes[$0] } ?? Int.max)
      }
    default:
      return items
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

  private func stableSort<T>(
    _ items: [T],
    key: (T) -> HistoryItem,
    by areInIncreasingOrder: (HistoryItem, HistoryItem) -> Bool
  ) -> [T] {
    items.enumerated().sorted { lhs, rhs in
      let lhsItem = key(lhs.element)
      let rhsItem = key(rhs.element)
      if areInIncreasingOrder(lhsItem, rhsItem) {
        return true
      }
      if areInIncreasingOrder(rhsItem, lhsItem) {
        return false
      }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }

}
// swiftlint:enable identifier_name
// swiftlint:enable type_name
