import AppKit
import Defaults

// swiftlint:disable identifier_name
// swiftlint:disable type_name
/// Sorts history items by a single total order: pin partition primary,
/// user-selected algorithm secondary.
class Sorter {
  /// Available sort criteria.
  enum By: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
    case lastCopiedAt
    case firstCopiedAt
    case numberOfCopies

    var id: Self { self }

    /// Localized user-facing name.
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

  /// Returns the items sorted by the single total order.
  ///
  /// `Defaults[.pinTo]` is read once and captured into the comparator so it is
  /// not re-fetched per comparison. The order is computed in a single pass
  /// (pin partition primary, algorithm secondary) — identical to the prior
  /// two-pass stable sort but with roughly half the comparisons and half the
  /// per-comparison `@Model` property faults fired from SQLite during load and
  /// every-copy reconcile. Shares the same order definition as
  /// `areInIncreasingOrder`, so an incremental insert via `BinaryInsertion`
  /// lands items at the same position a full sort would.
  func sort(_ items: [HistoryItem], by: By = Defaults[.sortBy]) -> [HistoryItem] {
    let pinTo = Defaults[.pinTo]
    return items.sorted(by: { areInIncreasingOrder($0, $1, by: by, pinTo: pinTo) })
  }

  /// Total order matching `sort(_:by:)`: pin partition primary, algorithm
  /// secondary. Reads `Defaults[.pinTo]` once per call.
  func areInIncreasingOrder(_ lhs: HistoryItem, _ rhs: HistoryItem, by: By = Defaults[.sortBy]) -> Bool {
    areInIncreasingOrder(lhs, rhs, by: by, pinTo: Defaults[.pinTo])
  }

  /// Total order with a caller-supplied `pinTo`, avoiding a `Defaults[.pinTo]`
  /// read per comparison when the caller already holds it.
  func areInIncreasingOrder(_ lhs: HistoryItem, _ rhs: HistoryItem, by: By, pinTo: PinsPosition) -> Bool {
    if byPinned(lhs, rhs, pinTo: pinTo) { return true }
    if byPinned(rhs, lhs, pinTo: pinTo) { return false }
    return bySortingAlgorithm(lhs, rhs, by)
  }

  /// Compares two items by the user-selected algorithm (newest/most-copied
  /// first).
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

  /// Returns true when `lhs` should sort before `rhs` purely on pin partition,
  /// according to the configured pin position.
  private func byPinned(_ lhs: HistoryItem, _ rhs: HistoryItem, pinTo: PinsPosition) -> Bool {
    if pinTo == .bottom {
      return (lhs.pin == nil) && (rhs.pin != nil)
    } else {
      return (lhs.pin != nil) && (rhs.pin == nil)
    }
  }
}

/// O(log n) lower-bound insertion index for an already-sorted
/// `RandomAccessCollection` ordered by `areInIncreasingOrder`.
///
/// Equal-or-greater elements stay put and `element` inserts after them. The
/// incremental consume path uses this to place a single new item at its sorted
/// position without re-sorting the whole array.
enum BinaryInsertion {
  /// Returns the index at which `element` should be inserted into `sorted`.
  static func index<C: RandomAccessCollection>(
    for element: C.Element,
    in sorted: C,
    by areInIncreasingOrder: (C.Element, C.Element) -> Bool
  ) -> Int where C.Index == Int {
    var low = sorted.startIndex
    var high = sorted.endIndex
    while low < high {
      let mid = low + (high - low) / 2
      if areInIncreasingOrder(sorted[mid], element) {
        low = mid + 1
      } else {
        high = mid
      }
    }
    return low
  }
}
// swiftlint:enable identifier_name
// swiftlint:enable type_name
