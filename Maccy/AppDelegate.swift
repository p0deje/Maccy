import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  private var hotKey: GlobalHotKey!
  private var maccy: Maccy!

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    maccy = Maccy()
    hotKey = GlobalHotKey(maccy.popUp)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    maccy.statusItem.isVisible = true
    return true
  }
}
