import Cocoa
import Sparkle

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  private var hotKey: GlobalHotKey!
  private var maccy: Maccy!

  func applicationWillFinishLaunching(_ notification: Notification) {
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      SUUpdater.shared()?.automaticallyChecksForUpdates = false
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    migrateUserDefaults()

    maccy = Maccy()
    hotKey = GlobalHotKey(maccy.popUp)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    maccy.statusItem.isVisible = true
    return true
  }

  private func migrateUserDefaults() {
    if UserDefaults.standard.migrations["2020-02-22-introduce-history-item"] != true {
      if let oldStorage = UserDefaults.standard.array(forKey: UserDefaults.Keys.storage) as? [String] {
        UserDefaults.standard.storage = oldStorage.compactMap({ item in
          if let data = item.data(using: .utf8) {
            return HistoryItem(value: data)
          } else {
            return nil
          }
        })
        UserDefaults.standard.migrations["2020-02-22-introduce-history-item"] = true
      }
    }

    if UserDefaults.standard.migrations["2020-02-22-history-item-add-copied-at"] != true {
      UserDefaults.standard.storage = UserDefaults.standard.storage.map({ item in
        let migratedItem = item
        migratedItem.firstCopiedAt = Date()
        migratedItem.lastCopiedAt = Date()
        return migratedItem
      })
      UserDefaults.standard.migrations["2020-02-22-history-item-add-copied-at"] = true
    }

    if UserDefaults.standard.migrations["2020-02-22-history-item-add-number-of-copies"] != true {
      UserDefaults.standard.storage = UserDefaults.standard.storage.map({ item in
        let migratedItem = item
        migratedItem.numberOfCopies = 1
        return migratedItem
      })
      UserDefaults.standard.migrations["2020-02-22-history-item-add-number-of-copies"] = true
    }
  }
}
