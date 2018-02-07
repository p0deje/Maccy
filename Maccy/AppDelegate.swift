import Cocoa
import HotKey

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  let clipboard = Clipboard()
  let history = History()
  let hotKey = HotKey(key: .c, modifiers: [.command, .shift])

  var maccy: Maccy {
    return Maccy(history: history, clipboard: clipboard)
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    maccy.start()
    hotKey.keyDownHandler = { self.maccy.popUp() }
  }
}
