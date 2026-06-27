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
    // Hoisted out of the comparator: `byPinned` previously read `Defaults[.pinTo]`
    // per comparison (O(n log n) Defaults reads per sort — once on `load()` and
    // again on every-copy `reconcileWithStore`). Read once here and capture it.
    // (render-chain S11; docs/audit/2026-06-22-render-chain-storms.md)
    let pinTo = Defaults[.pinTo]
    // Single-pass total order (pin-primary, algorithm-secondary) — identical
    // result to the prior two-pass (algorithm-then-pin) stable sort, but ONE
    // comparator pass instead of two: ~half the comparisons AND the
    // per-comparison @Model property faults (lastCopiedAt/firstCopiedAt/
    // numberOfCopies/pin) fired from SQLite during `load()` and every-copy
    // `reconcileWithStore`. Shares the same total order as
    // `areInIncreasingOrder`, so `sort` and `BinaryInsertion`'s incremental
    // insert now use one order definition (HistoryConsumeTests'
    // testConsumeIncrementalOrderMatchesFullSort guards the equivalence).
    return items.sorted(by: { areInIncreasingOrder($0, $1, by: by, pinTo: pinTo) })
  }

  /// Total order matching `sort(_:by:)` — pin partition primary, algorithm
  /// secondary. Hoists `Defaults[.pinTo]`/`[.sortBy]` once. For `BinaryInsertion`'s
  /// incremental insert (BS-4.4a): a single new item can be placed at its sorted
  /// position without re-sorting the whole array, producing the same order as
  /// `sort`.
  func areInIncreasingOrder(_ lhs: HistoryItem, _ rhs: HistoryItem, by: By = Defaults[.sortBy]) -> Bool {
    areInIncreasingOrder(lhs, rhs, by: by, pinTo: Defaults[.pinTo])
  }

  /// Hoisted-`pinTo` overload: avoids a `Defaults[.pinTo]` read per comparison
  /// when the caller (e.g. `sort`) already holds it. Same total order as the
  /// default-`pinTo` overload — pin partition primary, algorithm secondary.
  func areInIncreasingOrder(_ lhs: HistoryItem, _ rhs: HistoryItem, by: By, pinTo: PinsPosition) -> Bool {
    if byPinned(lhs, rhs, pinTo: pinTo) { return true }
    if byPinned(rhs, lhs, pinTo: pinTo) { return false }
    return bySortingAlgorithm(lhs, rhs, by)
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

  private func byPinned(_ lhs: HistoryItem, _ rhs: HistoryItem, pinTo: PinsPosition) -> Bool {
    if pinTo == .bottom {
      return (lhs.pin == nil) && (rhs.pin != nil)
    } else {
      return (lhs.pin != nil) && (rhs.pin == nil)
    }
  }
}

/// O(log n) insertion index for an already-sorted `RandomAccessCollection`
/// (ordered by `areInIncreasingOrder`). Lower-bound: equal-or-greater elements
/// stay put and `element` inserts after them. BS-4.4a's incremental consume uses
/// this to place a new item without re-sorting `all`.
enum BinaryInsertion {
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
