import AppIntents
import Cocoa

import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Sauce
import Sparkle
import Settings
import SwiftUI

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

    let panel = FloatingPanel(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
      title: Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy"
    ) {
      ContentView()
    }

    panel.center()
    panel.open()

    KeyboardShortcuts.onKeyUp(for: .popup) {
      if !panel.isPresented {
        panel.open()
      } else {
        panel.close()
      }
    }

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
    if Defaults[.migrations]["2024-07-01-version-2"] != true {
      // Start 2.x from scratch.
      Defaults.reset(.migrations)

      // Inverse hide* configuration keys.
      Defaults[.showFooter] = !UserDefaults.standard.bool(forKey: "hideFooter")
      Defaults[.showSearch] = !UserDefaults.standard.bool(forKey: "hideSearch")
      Defaults[.showTitle] = !UserDefaults.standard.bool(forKey: "hideTitle")
      UserDefaults.standard.removeObject(forKey: "hideFooter")
      UserDefaults.standard.removeObject(forKey: "hideSearch")
      UserDefaults.standard.removeObject(forKey: "hideTitle")

      Defaults[.migrations]["2024-07-01-version-2"] = true
    }
  }

  private func clearOrphanRecords() {
    let fetchRequest = NSFetchRequest<HistoryItemContentL>(entityName: "HistoryItemContent")
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
