import Cocoa

class Maccy: NSObject {
  @objc public let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

  private let about = About()
  private let clipboard = Clipboard()
  private let history = History()
  private let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApp.stop), keyEquivalent: "q")

  private var menu: Menu!

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

  private var filterMenuRect: NSRect {
    return NSRect(x: 0, y: 0, width: menu.menuWidth, height: UserDefaults.standard.hideSearch ? 1 : 29)
  }

  private var hideSearchObserver: NSKeyValueObservation?
  private var pasteByDefaultObserver: NSKeyValueObservation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?

  override init() {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.showInStatusBar: UserDefaults.Values.showInStatusBar])
    super.init()

    hideSearchObserver = UserDefaults.standard.observe(\.hideSearch, options: .new, changeHandler: { _, _ in
      self.menu.clear()
      self.menu.removeAllItems()

      self.populateHeader()
      self.populateItems()
      self.populateFooter()
    })

    pasteByDefaultObserver = UserDefaults.standard.observe(\.pasteByDefault, options: .new, changeHandler: { _, _ in
      self.menu.clear()
      self.populateItems()
    })

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new, changeHandler: { _, change in
      UserDefaults.standard.showInStatusBar = change.newValue!
    })

    menu = Menu(history: history, clipboard: clipboard)
    start()
  }

  deinit {
    hideSearchObserver?.invalidate()
    pasteByDefaultObserver?.invalidate()
    statusItemVisibilityObserver?.invalidate()
  }

  func popUp() {
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
  }

  private func start() {
    statusItem.button?.image = NSImage(named: "StatusBarMenuImage")
    statusItem.menu = menu
    statusItem.behavior = .removalAllowed
    statusItem.isVisible = UserDefaults.standard.showInStatusBar

    clipboard.onNewCopy(history.add)
    clipboard.onNewCopy(menu.prepend)
    clipboard.onRemovedCopy(history.removeRecent)
    clipboard.onRemovedCopy(menu.removeRecent)
    clipboard.startListening()

    populateHeader()
    populateItems()
    populateFooter()
  }

  private func populateHeader() {
    let headerItemView = FilterMenuItemView(frame: filterMenuRect)
    headerItemView.title = "Maccy"

    let headerItem = NSMenuItem()
    headerItem.title = "Maccy"
    headerItem.view = headerItemView
    headerItem.isEnabled = false

    menu.addItem(headerItem)
  }

  private func populateItems() {
    history.all().reversed().forEach(menu.prepend)
  }

  private func populateFooter() {
    menu.addItem(NSMenuItem.separator())
    menu.addItem(clearItem)
    if UserDefaults.standard.saratovSeparator {
      menu.addItem(NSMenuItem.separator())
    }
    menu.addItem(aboutItem)
    menu.addItem(quitItem)
  }

  @objc
  func clear(_ sender: NSMenuItem) {
    history.clear()
    menu.clear()
  }
}
