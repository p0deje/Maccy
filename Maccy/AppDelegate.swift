import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
  let clipboard = Clipboard()
  let history = History()
  let hotKey = GlobalHotKey()

  var maccy:Maccy

  override init(){
    self.maccy=Maccy(history: history, clipboard: clipboard)
    super.init()
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    maccy.start()
    hotKey.handler = { self.maccy.popUp() }
  }
}
