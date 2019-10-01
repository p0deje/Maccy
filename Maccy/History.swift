import AppKit

class History {
  init() {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.size: UserDefaults.Values.size])
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      clear()
    }
  }

  func all() -> [String] {
    var savedHistory = UserDefaults.standard.storage
    let maxSize = UserDefaults.standard.size

    while savedHistory.count > maxSize {
      savedHistory.remove(at: maxSize - 1)
    }

    return savedHistory
  }

  func add(_ string: String) {
    if UserDefaults.standard.ignoreEvents {
      return
    }

    if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return
    }

    remove(string)

    var history = all()
    let maxSize = UserDefaults.standard.size

    if history.count == maxSize {
      history.remove(at: maxSize - 1)
    }

    let newContents = [string] + history
    UserDefaults.standard.storage = newContents
  }

  func remove(_ string: String?) {
    guard let itemToRemove = string else {
      return
    }

    var history = all()
    if let index = history.firstIndex(of: itemToRemove) {
      history.remove(at: index)
    }

    UserDefaults.standard.storage = history
  }

  func removeRecent() {
    var history = all()
    if !history.isEmpty {
      history.removeFirst()
      UserDefaults.standard.storage = history
    }
  }

  func clear() {
    UserDefaults.standard.storage = []
  }
}
