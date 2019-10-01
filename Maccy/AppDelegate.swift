import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  private let clipboard = Clipboard()
  private let history = History()

  private var hotKey: GlobalHotKey!
  private var maccy: Maccy!

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    maccy = Maccy(history: history, clipboard: clipboard)
    maccy.start()
    hotKey = GlobalHotKey({ self.maccy.popUp() })
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    maccy.statusItem.isVisible = true
    return true
  }
}
