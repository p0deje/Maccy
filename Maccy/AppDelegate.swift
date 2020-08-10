import Cocoa
import KeyboardShortcuts
import Sauce
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

  func applicationWillTerminate(_ notification: Notification) {
    CoreDataManager.shared.saveContext()
  }

  // swiftlint:disable cyclomatic_complexity
  // swiftlint:disable function_body_length
  private func migrateUserDefaults() {
    if UserDefaults.standard.migrations["2020-02-22-introduce-history-item"] != true {
      if let oldStorage = UserDefaults.standard.array(forKey: UserDefaults.Keys.storage) as? [String] {
        UserDefaults.standard.storage = oldStorage.compactMap({ item in
          if let data = item.data(using: .utf8) {
            return HistoryItemOld(value: data)
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

    if UserDefaults.standard.migrations["2020-04-18-switch-storage-to-core-data"] != true {
      for item in UserDefaults.standard.storage {
        var content: HistoryItemContent
        if item.type == .image {
          content = HistoryItemContent(type: NSPasteboard.PasteboardType.tiff.rawValue, value: item.value)
        } else {
          content = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: item.value)
        }
        let newItem = HistoryItem(contents: [content])
        newItem.firstCopiedAt = item.firstCopiedAt
        newItem.lastCopiedAt = item.lastCopiedAt
        newItem.numberOfCopies = item.numberOfCopies
        newItem.pin = item.pin
      }
      CoreDataManager.shared.saveContext()
      UserDefaults.standard.migrations["2020-04-18-switch-storage-to-core-data"] = true
    }

    if UserDefaults.standard.migrations["2020-04-25-allow-custom-ignored-types"] != true {
      UserDefaults.standard.ignoredPasteboardTypes = [
        "de.petermaurer.TransientPasteboardType",
        "com.typeit4me.clipping",
        "Pasteboard generator type",
        "com.agilebits.onepassword",
        "net.antelle.keeweb"
      ]
      UserDefaults.standard.migrations["2020-04-25-allow-custom-ignored-types"] = true
    }

    if UserDefaults.standard.migrations["2020-06-19-use-keyboardshortcuts"] != true {
      if let keys = UserDefaults.standard.string(forKey: "hotKey") {
        var keysList = keys.split(separator: "+")

        if let keyString = keysList.popLast() {
          if let key = Key(character: String(keyString), virtualKeyCode: nil) {
            var modifiers: NSEvent.ModifierFlags = []
            for keyString in keysList {
              switch keyString {
              case "command":
                modifiers.insert(.command)
              case "control":
                modifiers.insert(.control)
              case "option":
                modifiers.insert(.option)
              case "shift":
                modifiers.insert(.shift)
              default: ()
              }
            }

            if let keyboardShortcutKey = KeyboardShortcuts.Key(rawValue: Int(key.QWERTYKeyCode)) {
              let shortcut = KeyboardShortcuts.Shortcut(keyboardShortcutKey, modifiers: modifiers)
              if let encoded = try? JSONEncoder().encode(shortcut) {
                if let hotKeyString = String(data: encoded, encoding: .utf8) {
                  let preferenceKey = "KeyboardShortcuts_\(KeyboardShortcuts.Name.popup.rawValue)"
                  UserDefaults.standard.set(hotKeyString, forKey: preferenceKey)
                }
              }
            }
          }
        }
      }

      UserDefaults.standard.migrations["2020-06-19-use-keyboardshortcuts"] = true
    }

  }
  // swiftlint:enable cyclomatic_complexity
  // swiftlint:enable function_body_length
}
