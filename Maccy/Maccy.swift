import Cocoa
import LoginServiceKit
import Preferences
import Sparkle

class Maccy: NSObject {
  @objc public let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

  private let about = About()
  private let clipboard = Clipboard()
  private let history = History()
  private var menu: Menu!
  private var window: NSWindow!

  private lazy var preferencesWindowController = PreferencesWindowController(
    preferencePanes: [
      GeneralPreferenceViewController(),
      AppearancePreferenceViewController(),
      AdvancedPreferenceViewController()
    ]
  )

  private var filterMenuRect: NSRect {
    return NSRect(x: 0, y: 0, width: menu.menuWidth, height: UserDefaults.standard.hideSearch ? 1 : 29)
  }

  private var ignoreEventsObserver: NSKeyValueObservation?
  private var hideFooterObserver: NSKeyValueObservation?
  private var hideSearchObserver: NSKeyValueObservation?
  private var hideTitleObserver: NSKeyValueObservation?
  private var pasteByDefaultObserver: NSKeyValueObservation?
  private var statusItemConfigurationObserver: NSKeyValueObservation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?

  override init() {
    UserDefaults.standard.register(defaults: [UserDefaults.Keys.showInStatusBar: UserDefaults.Values.showInStatusBar])
    super.init()

    ignoreEventsObserver = UserDefaults.standard.observe(\.ignoreEvents, options: .new, changeHandler: { _, change in
      self.statusItem.button?.appearsDisabled = change.newValue!
    })
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
    statusItemConfigurationObserver = UserDefaults.standard.observe(\.showInStatusBar,
                                                                    options: .new,
                                                                    changeHandler: { _, change in
      if self.statusItem.isVisible != change.newValue! {
        self.statusItem.isVisible = change.newValue!
      }
    })
    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new, changeHandler: { _, change in
      if UserDefaults.standard.showInStatusBar != change.newValue! {
        UserDefaults.standard.showInStatusBar = change.newValue!
      }
    })

    menu = Menu(history: history, clipboard: clipboard)
    start()
  }

  deinit {
    ignoreEventsObserver?.invalidate()
    hideFooterObserver?.invalidate()
    hideSearchObserver?.invalidate()
    hideTitleObserver?.invalidate()
    pasteByDefaultObserver?.invalidate()
    statusItemConfigurationObserver?.invalidate()
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
    statusItem.button?.appearsDisabled = UserDefaults.standard.ignoreEvents
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
    MenuFooter.allCases.map({ $0.menuItem }).forEach({ item in
      item.action = #selector(menuItemAction)
      item.target = self
      menu.addItem(item)
    })
  }

  @objc
  func menuItemAction(_ sender: NSMenuItem) {
    if let tag = MenuFooter(rawValue: sender.tag) {
      switch tag {
      case .about:
        about.openAbout(sender)
      case .clear:
        clearUnpinned()
      case .clearAll:
        clearAll()
      case .quit:
        NSApp.stop(sender)
      case .preferences:
        preferencesWindowController.show()
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

  private func rebuild() {
    menu.clearAll()
    menu.removeAllItems()

    populateHeader()
    populateFooter()
  }
}
