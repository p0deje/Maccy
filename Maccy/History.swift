import AppKit

class History {
  private let storageKey = "history"
  private let sizeKey = "historySize"

  init() {
    UserDefaults.standard.register(defaults: [sizeKey: 999])
  }

  func all() -> [String] {
    guard var savedHistory = UserDefaults.standard.array(forKey: storageKey) as? [String] else {
      return []
    }

    let maxSize = UserDefaults.standard.integer(forKey: sizeKey)
    while savedHistory.count > maxSize {
      savedHistory.remove(at: maxSize - 1)
    }

    return savedHistory
  }

  func add(_ string: String) {
    var history = all()
    let maxSize = UserDefaults.standard.integer(forKey: sizeKey)

    if let index = history.firstIndex(of: string) {
      history.remove(at: index)
    } else if history.count == maxSize {
      history.remove(at: maxSize - 1)
    }

    let newContents = [string] + history
    UserDefaults.standard.set(newContents, forKey: storageKey)
  }

  func removeRecent() {
    var history = all()
    if !history.isEmpty {
      history.removeFirst()
      UserDefaults.standard.set(history, forKey: storageKey)
    }
  }

  func clear() {
    UserDefaults.standard.set([], forKey: storageKey)
  }
}
