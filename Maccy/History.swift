import AppKit

class History {
  public var all: [HistoryItem] {
    var unpinned = HistoryItem.unpinned()
    while unpinned.count > UserDefaults.standard.size {
      remove(unpinned.removeLast())
    }

    return HistoryItem.all()
  }

  init() {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.size: UserDefaults.Values.size])
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      clear()
    }
  }

  func add(_ item: HistoryItem) {
    if let existingHistoryItem = findDuplicateItem(item) {
      existingHistoryItem.lastCopiedAt = item.firstCopiedAt
      existingHistoryItem.numberOfCopies += 1
      remove(item)
    }

    CoreDataManager.shared.saveContext()
  }

  func update(_ item: HistoryItem) {
    CoreDataManager.shared.saveContext()
  }

  func remove(_ item: HistoryItem) {
    CoreDataManager.shared.viewContext.delete(item)
    CoreDataManager.shared.saveContext()
  }

  func clear() {
    all.forEach(remove(_:))
  }

  private func findDuplicateItem(_ item: HistoryItem) -> HistoryItem? {
    let duplicates = all.filter({ $0 == item })
    if duplicates.count > 1 {
      return duplicates.last
    } else {
      return nil
    }
  }
}
