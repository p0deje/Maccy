import Cocoa
import Intents
import KeyboardShortcuts
import LaunchAtLogin
import Sauce
import Sparkle

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  @IBOutlet weak var pasteMenuItem: NSMenuItem!

  private var hotKey: GlobalHotKey!
  private var maccy: Maccy!

  func applicationWillFinishLaunching(_ notification: Notification) {
    if ProcessInfo.processInfo.arguments.contains("ui-testing") {
      SPUUpdater(hostBundle: Bundle.main,
                 applicationBundle: Bundle.main,
                 userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
                 delegate: nil)
        .automaticallyChecksForUpdates = false
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    migrateUserDefaults()
    clearOrphanRecords()

    maccy = Maccy()
    hotKey = GlobalHotKey(maccy.popUp)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    maccy.popUp()
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    if UserDefaults.standard.clearOnQuit {
      maccy.clearUnpinned(suppressClearAlert: true)
    }
    CoreDataManager.shared.saveContext()
  }

  @available(macOS 11.0, *)
  func application(_ application: NSApplication, handlerFor intent: INIntent) -> Any? {
    if intent is SelectIntent {
      return SelectIntentHandler(maccy)
    } else if intent is ClearIntent {
      return ClearIntentHandler(maccy)
    } else if intent is GetIntent {
      return GetIntentHandler(maccy)
    } else if intent is DeleteIntent {
      return DeleteIntentHandler(maccy)
    }

    return nil
  }

  private func migrateUserDefaults() {
  }

  private func clearOrphanRecords() {
    let fetchRequest = NSFetchRequest<HistoryItemContent>(entityName: "HistoryItemContent")
    fetchRequest.predicate = NSPredicate(format: "item == nil")
    do {
      try CoreDataManager.shared.viewContext
        .fetch(fetchRequest)
        .forEach(CoreDataManager.shared.viewContext.delete(_:))
      CoreDataManager.shared.saveContext()
    } catch {
      // Something went wrong, but it's no big deal.
    }
  }
}
