import Cocoa
import LoginServiceKit
import Sparkle

class Maccy: NSObject {
  @objc public let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

  private let about = About()
  private let clipboard = Clipboard()
  private let history = History()
  private var menu: Menu!

  private var footerItems: [NSMenuItem] {
    var footerItems: [(tag: MenuTag, isChecked: Bool, key: String)] = [
      (.separator, false, ""),
      (.clear, false, ""),
      (.checkForUpdates, false, ""),
      (.launchAtLogin, LoginServiceKit.isExistLoginItems(), "")
    ]

    if UserDefaults.standard.saratovSeparator {
      footerItems.append((.separator, false, ""))
    }

    footerItems += [
      (.about, false, ""),
      (.quit, false, "q")
    ]

    return footerItems.map({ item -> NSMenuItem in
      if item.tag == .separator {
        return NSMenuItem.separator()
      } else {
        let menuItem = NSMenuItem(title: item.tag.string,
                                  action: #selector(menuItemAction),
                                  keyEquivalent: item.key)
        menuItem.tag = item.tag.rawValue
        menuItem.state = item.isChecked ? .on: .off
        menuItem.target = self
        return menuItem
      }
    })
  }

  private var filterMenuRect: NSRect {
    return NSRect(x: 0, y: 0, width: menu.menuWidth, height: UserDefaults.standard.hideSearch ? 1 : 29)
  }

  private var hideFooterObserver: NSKeyValueObservation?
  private var hideSearchObserver: NSKeyValueObservation?
  private var hideTitleObserver: NSKeyValueObservation?
  private var pasteByDefaultObserver: NSKeyValueObservation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?

  override init() {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.showInStatusBar: UserDefaults.Values.showInStatusBar])
    super.init()

    hideFooterObserver = UserDefaults.standard.observe(\.hideFooter, options: .new, changeHandler: { _, _ in
      self.rebuild()
    })
    hideSearchObserver = UserDefaults.standard.observe(\.hideSearch, options: .new, changeHandler: { _, _ in
      self.rebuild()
    })
    hideTitleObserver = UserDefaults.standard.observe(\.hideTitle, options: .new, changeHandler: { _, _ in
      self.rebuild()
    })
    pasteByDefaultObserver = UserDefaults.standard.observe(\.pasteByDefault, options: .new, changeHandler: { _, _ in
      self.rebuild()
    })

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new, changeHandler: { _, change in
      UserDefaults.standard.showInStatusBar = change.newValue!
    })

    menu = Menu(history: history, clipboard: clipboard)
    start()
  }

  deinit {
    hideFooterObserver?.invalidate()
    hideSearchObserver?.invalidate()
    hideTitleObserver?.invalidate()
    pasteByDefaultObserver?.invalidate()
    statusItemVisibilityObserver?.invalidate()
  }

  func popUp() {
    if UserDefaults.standard.popupPosition == "center", let screen = NSScreen.main {
      let topLeftX = (screen.frame.width - menu.size.width) / 2
      let topLeftY = (screen.frame.height + menu.size.height) / 2
      menu.popUp(positioning: nil, at: NSPoint(x: topLeftX, y: topLeftY), in: nil)
    } else {
      menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
  }

  private func start() {
    statusItem.button?.image = NSImage(named: "StatusBarMenuImage")
    statusItem.menu = menu
    statusItem.behavior = .removalAllowed
    statusItem.isVisible = UserDefaults.standard.showInStatusBar

    clipboard.onNewCopy(history.add)
    clipboard.startListening()

    populateHeader()
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

  private func populateFooter() {
    guard !UserDefaults.standard.hideFooter else {
      return
    }

    for item in footerItems {
      menu.addItem(item)
    }
  }

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
      case .checkForUpdates:
        SUUpdater.shared()?.checkForUpdates(self)
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
    if sender.state == .off {
      LoginServiceKit.addLoginItems()
      sender.state = .on
    } else {
      LoginServiceKit.removeLoginItems()
      sender.state = .off
    }
  }

  private func rebuild() {
    menu.clear()
    menu.removeAllItems()

    populateHeader()
    populateFooter()
  }
}
