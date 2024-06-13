import AppIntents
import Cocoa

import Defaults
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

    AppDependencyManager.shared.add(key: "maccy", dependency: self.maccy)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    maccy.popUp()
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    if Defaults[.clearOnQuit] {
      maccy.clearUnpinned(suppressClearAlert: true)
    }
    CoreDataManager.shared.saveContext()
  }

  private func migrateUserDefaults() {
    // Start 2.x from scratch
    Defaults.reset(.migrations)
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
