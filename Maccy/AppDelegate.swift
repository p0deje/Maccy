import Cocoa
import HotKey

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  let clipboard = Clipboard()
  let history = History()
  let hotKey = HotKey(key: .c, modifiers: [.command, .shift])

  var menu: Menu {
    return Menu(history: history,
                clipboard: clipboard)
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    menu.start()
    hotKey.keyDownHandler = { self.menu.popUp() }
  }
}
