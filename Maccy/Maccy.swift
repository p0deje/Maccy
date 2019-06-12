import Cocoa

class Maccy {
  private let about = About()
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let menu = Menu(title: "Maccy")
  private let showInStatusBar = "showInStatusBar"

  private let history: History
  private let clipboard: Clipboard

  private var clearItem: NSMenuItem {
    let item = NSMenuItem(title: "Clear", action: #selector(clear), keyEquivalent: "")
    item.target = self
    return item
  }

  private var aboutItem: NSMenuItem {
    let item = NSMenuItem(title: "About", action: #selector(about.openAbout), keyEquivalent: "")
    item.target = about
    return item
  }

  init(history: History, clipboard: Clipboard) {
    self.history = history
    self.clipboard = clipboard

    UserDefaults.standard.register(defaults: [showInStatusBar: true])
  }

  func start() {
    if UserDefaults.standard.bool(forKey: showInStatusBar) {
      statusItem.button!.image = NSImage(named: "StatusBarMenuImage")
      statusItem.menu = menu
    }

    refresh()

    clipboard.onNewCopy(history.add)
    clipboard.onNewCopy({ (_ string: String) -> Void in self.refresh() })
    clipboard.onRemovedCopy(history.removeLast)
    clipboard.onRemovedCopy({ self.refresh() })

    clipboard.startListening()
  }

  func popUp() {
//    refresh()
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
  }

  private func refresh() {
    let filterItem = menu.item(at: 0)
    menu.removeAllItems()
    menu.addItem(filterItem!)
    populateItems()
    populateFooter()
  }

  private func populateItems() {
    for entry in history.all() {
      menu.addItem(historyItem(entry))
    }
  }

  private func populateFooter() {
    menu.addItem(NSMenuItem.separator())
    menu.addItem(clearItem)
    menu.addItem(aboutItem)
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.stop), keyEquivalent: "q"))
  }

  private func addItem(_ string: String) {
    menu.insertItem(historyItem(string), at: 0)
  }

  private func historyItem(_ title: String) -> HistoryMenuItem {
    return HistoryMenuItem(title: title, clipboard: clipboard)
  }

  @objc
  func clear(_ sender: NSMenuItem) {
    history.clear()
    menu.removeAllItems()
    populateFooter()
  }
}
