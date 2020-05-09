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
    var footerItems: [(tag: MenuTag, isChecked: Bool, isAlternate: Bool, key: String, tooltip: String)] = [
      (.separator, false, false, "", ""),
      (.clear, false, false, "", NSLocalizedString("Clear unpinned items.\nSelect with ⌥ to clear all.", comment: "")),
      (.clearAll, false, true, "", NSLocalizedString("Clear all items.", comment: "")),
      (.checkForUpdates, false, false, "", NSLocalizedString("Check for updates now.", comment: "")),
      (.launchAtLogin, LoginServiceKit.isExistLoginItems(), false, "", NSLocalizedString("Automatically launch at login.", comment: ""))
    ]

    if UserDefaults.standard.saratovSeparator {
      footerItems.append((.separator, false, false, "", ""))
    }

    footerItems += [
      (.about, false, false, "", NSLocalizedString("Read more about application.", comment: "")),
      (.quit, false, false, "q", NSLocalizedString("Quit application.", comment: ""))
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
        if item.isAlternate {
          menuItem.isAlternate = true
          menuItem.keyEquivalentModifierMask = [.option]
        }
        menuItem.target = self
        menuItem.toolTip = item.tooltip
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
    switch UserDefaults.standard.popupPosition {
    case "center":
      if let screen = NSScreen.main {
        let topLeftX = (screen.frame.width - menu.size.width) / 2
        let topLeftY = (screen.frame.height + menu.size.height) / 2
        menu.popUp(positioning: nil, at: NSPoint(x: topLeftX, y: topLeftY), in: nil)
      }
    case "statusItem":
      if let button = statusItem.button, let window = button.window {
        menu.popUp(positioning: nil, at: window.frame.origin, in: nil)
      }
    default:
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
        clearUnpinned()
      case .clearAll:
        clearAll()
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

  private func clearUnpinned() {
    history.all.filter({ $0.pin == nil }).forEach(history.remove(_:))
    menu.clearUnpinned()
  }

  private func clearAll() {
    history.clear()
    menu.clearAll()
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
    menu.clearAll()
    menu.removeAllItems()

    populateHeader()
    populateFooter()
  }
}
