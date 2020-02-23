import AppKit

// swiftlint:disable identifier_name
class Sorter {
  private var by: String

  init(by: String) {
    self.by = by
  }

  public func sort(_ items: [HistoryItem]) -> [HistoryItem] {
    return items.sorted(by: { lhs, rhs in
      switch by {
      case "firstCopiedAt":
        return lhs.firstCopiedAt < rhs.firstCopiedAt
      case "numberOfCopies":
        return lhs.numberOfCopies < rhs.numberOfCopies
      default:
        return lhs.lastCopiedAt < rhs.lastCopiedAt
      }
    })
  }
}
