import AppKit

class History {
  public var all: [HistoryItem] {
    get {
      while UserDefaults.standard.storage.count > UserDefaults.standard.size {
        UserDefaults.standard.storage.removeLast()
      }
      return UserDefaults.standard.storage
    }

    set { UserDefaults.standard.storage = newValue }
  }

  init() {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.size: UserDefaults.Values.size])
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      clear()
    }
  }

  func add(_ item: HistoryItem) {
    if UserDefaults.standard.ignoreEvents {
      return
    }

    if item.typesWithData[.string] != nil, let string = String(data: item.typesWithData[.string]!, encoding: .utf8) {
      if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return
      }
    }

    if let existingHistoryItem = all.first(where: { $0 == item }) {
      existingHistoryItem.lastCopiedAt = Date()
      existingHistoryItem.numberOfCopies += 1
      update(existingHistoryItem)
    } else {
      if all.count == UserDefaults.standard.size {
        all.removeLast()
      }
      all = [item] + all
    }
  }

  func update(_ item: HistoryItem) {
    if let itemIndex = all.firstIndex(of: item) {
      all.remove(at: itemIndex)
      all.insert(item, at: itemIndex)
    }
  }

  func remove(_ item: HistoryItem) {
    all.removeAll(where: { $0 == item })
  }

  func clear() {
    all.removeAll()
  }
}
