import Cocoa

class Maccy {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let menu = Menu(title: "Maccy")

  private let history: History
  private let clipboard: Clipboard

  private var clearItem: NSMenuItem {
    let item = NSMenuItem(title: "Clear", action: #selector(clear), keyEquivalent: "c")
    item.target = self
    return item
  }

  private var aboutItem: NSMenuItem {
    let item = NSMenuItem(title: "About", action: #selector(openAbout), keyEquivalent: "")
    item.target = self
    return item
  }

  init(history: History, clipboard: Clipboard) {
    self.history = history
    self.clipboard = clipboard
  }

  func start() {
    statusItem.button!.image = NSImage(named: NSImage.Name(rawValue: "StatusBarMenuImage"))
    statusItem.menu = menu

    refresh()

    clipboard.onNewCopy(history.add)
    clipboard.onNewCopy({ (_ string: String) -> Void in self.refresh() })
    clipboard.startListening()
  }

  func popUp() {
    refresh()
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

  @objc
  func openAbout(_ sender: NSMenuItem) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(nil)
  }
}
