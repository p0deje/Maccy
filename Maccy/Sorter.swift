import AppKit

class Sorter {
  public func sort(_ items: [HistoryItem]) -> [HistoryItem] {
    return items.sorted(by: { $0.lastCopiedAt < $1.lastCopiedAt })
  }
}
