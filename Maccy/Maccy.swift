import Cocoa

class Maccy {
  private let about = About()
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let menu = Menu(title: "Maccy")

  private let showInStatusBar = "showInStatusBar"
  private let pasteByDefault = "pasteByDefault"

  private let history: History
  private let clipboard: Clipboard

  private var clearItem: NSMenuItem {
    let item = NSMenuItem(title: "Clear", action: #selector(clear), keyEquivalent: "⌦")
    item.keyEquivalentModifierMask = .control
    item.target = self
    return item
  }
  
  private var prefItem: NSMenuItem {
    let item = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
    let prefMenu = NSMenu()
    prefMenu.addItem(pasteByDefaultItem)
    prefMenu.addItem(NSMenuItem.separator())
    prefMenu.addItem(historySizeItem)
    prefMenu.addItem(hotKeyItem)
    prefMenu.addItem(howToItem)
    item.submenu = prefMenu
    item.target = self
    return item
  }
  
  private var pasteByDefaultItem: NSMenuItem {
    let item = NSMenuItem(title: "Paste by Default", action: #selector(togglePasteByDefault), keyEquivalent: "")
    item.target = self
    if UserDefaults.standard.bool(forKey: pasteByDefault) {
      item.state = .on
    } else {
      item.state = .off
    }
    return item
  }
  private var howToItem: NSMenuItem {
    let item = NSMenuItem()
    item.title = "How to configure?"
    item.action = #selector(openHowToConfig)
    item.indentationLevel = 1
    item.target = self
    return item
  }
  private var historySizeItem: NSMenuItem {
    let historySize = UserDefaults.standard.integer(forKey: "historySize")
    let item = NSMenuItem()
    item.title = "History Size: " + String(historySize)
    item.target = self
    return item
  }
  private var hotKeyItem: NSMenuItem {
    let hotKey = UserDefaults.standard.string(forKey: "hotKey")
    let item = NSMenuItem()
    item.title = "Hotkey: " + hotKey!
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

    UserDefaults.standard.register(defaults: [showInStatusBar: true, pasteByDefault: false])
  }

  func start() {
    if !UserDefaults.standard.bool(forKey: showInStatusBar) {
      statusItem.isVisible = false
    }

    statusItem.button!.image = NSImage(named: "StatusBarMenuImage")
    statusItem.menu = menu
    statusItem.behavior = .removalAllowed

    refresh()

    clipboard.onNewCopy(history.add)
    clipboard.onNewCopy({ (_ string: String) -> Void in self.refresh() })
    clipboard.onRemovedCopy(history.removeRecent)
    clipboard.onRemovedCopy({ self.refresh() })

    clipboard.startListening()
  }

  func popUp() {
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
  }

  private func refresh() {
    menu.allItems.removeAll()
    menu.addSearchItem()
    populateItems()
    populateFooter()
  }

  private func populateItems() {
    let pasteByDefault = UserDefaults.standard.bool(forKey: self.pasteByDefault)
    for entry in history.all() {
      if pasteByDefault {
        addPasteSearchItem(entry, alt: false)
        addCopySearchItem(entry, alt: true)
      } else {
        addCopySearchItem(entry, alt: false)
        addPasteSearchItem(entry, alt: true)
      }
    }
  }

  private func populateFooter() {
    menu.addItem(NSMenuItem.separator())
    menu.addItem(clearItem)
    menu.addItem(prefItem)
    menu.addItem(aboutItem)
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.stop), keyEquivalent: "q"))
  }

  private func addCopySearchItem(_ entry: String, alt: Bool) {
    let menuItem = HistoryMenuItem(title: entry, onSelected: copy(_:))
    if alt {
      alternate(menuItem)
    }
    menu.addItem(menuItem)
  }

  private func addPasteSearchItem(_ entry: String, alt: Bool) {
    let menuItem = HistoryMenuItem(title: entry, onSelected: { item in
      self.copy(item)
      self.clipboard.paste()
    })
    if alt {
      alternate(menuItem)
    }
    menu.addItem(menuItem)
  }

  private func alternate(_ menuItem: HistoryMenuItem) {
    menuItem.keyEquivalentModifierMask = [.option]
    menuItem.isHidden = true
    menuItem.isAlternate = true
  }

  private func copy(_ item: HistoryMenuItem) {
    guard let title = item.fullTitle else {
      return
    }

    clipboard.copy(title)
  }

  @objc
  func clear(_ sender: NSMenuItem) {
    history.clear()
    refresh()
  }
  
  @objc
  func togglePasteByDefault(_ sender: NSMenuItem) {
    let pasteState = UserDefaults.standard.bool(forKey: pasteByDefault)
    UserDefaults.standard.set(!pasteState, forKey: pasteByDefault)
    if pasteState {
      sender.state = .off
    } else {
      sender.state = .on
    }
    refresh()
  }
  
  @objc
  func openHowToConfig(_ sender: NSMenuItem) {
    NSWorkspace.shared.open(URL(string: "https://github.com/p0deje/Maccy#customization")!)
  }
}
