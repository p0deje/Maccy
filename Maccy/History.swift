import AppKit

class History {
  private var storageKey = "history"
  private var sizeKey = "historySize"

  init() {
    UserDefaults.standard.register(defaults: [sizeKey: 999])
  }

  func all() -> [String] {
    guard let savedHistory = UserDefaults.standard.array(forKey: storageKey) else {
      return []
    }

    var history = savedHistory as! [String]
    let maxSize = UserDefaults.standard.integer(forKey: sizeKey)
    while history.count > maxSize {
      history.remove(at: maxSize - 1)
    }
    return history
  }

  func add(_ string: String) {
    var history = all()
    let maxSize = UserDefaults.standard.integer(forKey: sizeKey)

    if let index = history.index(of: string) {
      history.remove(at: index)
    } else if history.count == maxSize {
      history.remove(at: maxSize - 1)
    }

    let newContents = [string] + history
    UserDefaults.standard.set(newContents, forKey: storageKey)
  }

  func clear() {
    UserDefaults.standard.set([], forKey: storageKey)
  }
}
