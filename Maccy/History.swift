import AppKit

class History {
  private let sizeKey = "historySize"

  private var storageKey: String {
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      return "historyUITests"
    } else {
      return "history"
    }
  }

  private let ignoreEventsKey = "ignoreEvents"

  init() {
    UserDefaults.standard.register(defaults: [sizeKey: 200])
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      clear()
    }
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
    if UserDefaults.standard.bool(forKey: ignoreEventsKey) {
      return
    }

    remove(string)

    var history = all()
    let maxSize = UserDefaults.standard.integer(forKey: sizeKey)

    if history.count == maxSize {
      history.remove(at: maxSize - 1)
    }

    let newContents = [string] + history
    UserDefaults.standard.set(newContents, forKey: storageKey)
  }

  func remove(_ string: String?) {
    guard let itemToRemove = string else {
      return
    }

    var history = all()
    if let index = history.firstIndex(of: itemToRemove) {
      history.remove(at: index)
    }

    UserDefaults.standard.set(history, forKey: storageKey)
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
