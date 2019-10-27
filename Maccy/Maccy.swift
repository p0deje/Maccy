import Cocoa
import LaunchAtLogin

class Maccy: NSObject {
  @objc public let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

  private let about = About()
  private let clipboard = Clipboard()
  private let history = History()
  private var menu: Menu!
  private var pasteByDefaultObserver: NSKeyValueObservation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?

  override init() {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.showInStatusBar: UserDefaults.Values.showInStatusBar])
    super.init()

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
    let headerItemView = FilterMenuItemView(frame: NSRect(x: 0, y: 0, width: menu.menuWidth, height: 29))
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
    let footerItems: [(tag: MenuTag, isChecked: Bool, key: String)?] = [
      (.separator, false, ""),
      (.clear, false, ""),
      (.launchAtLogin, LaunchAtLogin.isEnabled, ""),
      UserDefaults.standard.saratovSeparator ? (.separator, false, ""): nil,
      (.about, false, ""),
      (.quit, false, "q")
    ]
    footerItems
      .compactMap({ $0 })
      .map({ item ->  NSMenuItem in
      if item.tag == .separator {
        return NSMenuItem.separator()
      }
      let menuItem = NSMenuItem(title: item.tag.string, action: #selector(menuItemAction), keyEquivalent: item.key)
      menuItem.tag = item.tag.rawValue
      menuItem.state = item.isChecked ? .on: .off
      return menuItem
    }).forEach({
      $0.target = self
      menu.addItem($0)
    })
  }
}

// MARK: - Menu actions

extension Maccy {
  @objc
  func menuItemAction(_ sender: NSMenuItem) {
    if let tag = MenuTag(rawValue: sender.tag) {
      switch tag {
      case .about:
        about.openAbout(sender)
      case .clear:
        clear()
      case .launchAtLogin:
        toggleLaunchAtLogin(sender)
      case .quit:
        NSApp.stop(sender)
      default:
        break
      }
    }
  }

  private func clear() {
    history.clear()
    menu.clear()
  }

  private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
    sender.state = (sender.state == .off) ? .on: .off
    LaunchAtLogin.isEnabled = sender.state == .on
  }
}
