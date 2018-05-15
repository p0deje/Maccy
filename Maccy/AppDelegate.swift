import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  let clipboard = Clipboard()
  let history = History()
  let hotKey = GlobalHotKey()
  
  var maccy: Maccy {
    return Maccy(history: history, clipboard: clipboard)
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    maccy.start()
    hotKey.handler = { self.maccy.popUp() }
  }
}
