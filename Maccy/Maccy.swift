import Cocoa
import KeyboardShortcuts
import Settings

// swiftlint:disable type_body_length
class Maccy: NSObject {
  static var returnFocusToPreviousApp = true

  @objc let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  var selectedItem: HistoryItem? { (menu.highlightedItem as? HistoryMenuItem)?.item }

  private let statusItemTitleMaxLength = 20

  private let about = About()
  private let clipboard = Clipboard.shared
  private let history = History()
  private var menu: Menu!
  private var menuController: MenuController!

  private var clearAlert: NSAlert {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("clear_alert_message", comment: "")
    alert.informativeText = NSLocalizedString("clear_alert_comment", comment: "")
    alert.addButton(withTitle: NSLocalizedString("clear_alert_confirm", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("clear_alert_cancel", comment: ""))
    alert.showsSuppressionButton = true
    return alert
  }

  private lazy var settingsWindowController = SettingsWindowController(
    panes: [
      GeneralSettingsViewController(),
      StorageSettingsViewController(),
      AppearanceSettingsViewController(),
      PinsSettingsViewController(),
      IgnoreSettingsViewController(),
      AdvancedSettingsViewController()
    ]
  )

  private var clipboardCheckIntervalObserver: NSKeyValueObservation?
  private var enabledPasteboardTypesObserver: NSKeyValueObservation?
  private var ignoreEventsObserver: NSKeyValueObservation?
  private var imageHeightObserver: NSKeyValueObservation?
  private var hideFooterObserver: NSKeyValueObservation?
  private var hideSearchObserver: NSKeyValueObservation?
  private var hideTitleObserver: NSKeyValueObservation?
  private var maxMenuItemLengthObserver: NSKeyValueObservation?
  private var pasteByDefaultObserver: NSKeyValueObservation?
  private var pinToObserver: NSKeyValueObservation?
  private var removeFormattingByDefaultObserver: NSKeyValueObservation?
  private var sortByObserver: NSKeyValueObservation?
  private var showSpecialSymbolsObserver: NSKeyValueObservation?
  private var showRecentCopyInMenuBarObserver: NSKeyValueObservation?
  private var statusItemConfigurationObserver: NSKeyValueObservation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?
  private var statusItemChangeObserver: NSKeyValueObservation?

  override init() {
    UserDefaults.standard.register(defaults: [
      UserDefaults.Keys.clipboardCheckInterval: UserDefaults.Values.clipboardCheckInterval,
      UserDefaults.Keys.imageMaxHeight: UserDefaults.Values.imageMaxHeight,
      UserDefaults.Keys.maxMenuItems: UserDefaults.Values.maxMenuItems,
      UserDefaults.Keys.maxMenuItemLength: UserDefaults.Values.maxMenuItemLength,
      UserDefaults.Keys.previewDelay: UserDefaults.Values.previewDelay,
      UserDefaults.Keys.showInStatusBar: UserDefaults.Values.showInStatusBar,
      UserDefaults.Keys.showSpecialSymbols: UserDefaults.Values.showSpecialSymbols
    ])

    super.init()
    initializeObservers()
    disableUnusedGlobalHotkeys()

    menu = Menu(history: history, clipboard: Clipboard.shared)
    menuController = MenuController(menu, statusItem)
    start()
  }

  deinit {
    clipboardCheckIntervalObserver?.invalidate()
    enabledPasteboardTypesObserver?.invalidate()
    ignoreEventsObserver?.invalidate()
    hideFooterObserver?.invalidate()
    hideSearchObserver?.invalidate()
    hideTitleObserver?.invalidate()
    maxMenuItemLengthObserver?.invalidate()
    pasteByDefaultObserver?.invalidate()
    pinToObserver?.invalidate()
    removeFormattingByDefaultObserver?.invalidate()
    sortByObserver?.invalidate()
    showRecentCopyInMenuBarObserver?.invalidate()
    showSpecialSymbolsObserver?.invalidate()
    statusItemConfigurationObserver?.invalidate()
    statusItemVisibilityObserver?.invalidate()
    statusItemChangeObserver?.invalidate()
  }

  func popUp() {
    menuController.popUp()
  }

  func select(position: Int) -> String? {
    return menu.select(position: position)
  }

  func delete(position: Int) -> String? {
    return menu.delete(position: position)
  }

  func item(at position: Int) -> HistoryItem? {
    return menu.historyItem(at: position)
  }

  func clearUnpinned(suppressClearAlert: Bool = false) {
    withClearAlert(suppressClearAlert: suppressClearAlert) {
      self.history.clearUnpinned()
      self.menu.clearUnpinned()
      self.clipboard.clear()
      self.updateMenuTitle()
    }
  }

  private func start() {
    statusItem.behavior = .removalAllowed
    statusItem.isVisible = UserDefaults.standard.showInStatusBar

    updateStatusMenuIcon(UserDefaults.standard.menuIcon)

    clipboard.onNewCopy(history.add)
    clipboard.onNewCopy(menu.add)
    clipboard.onNewCopy(updateMenuTitle)
    clipboard.start()

    populateHeader()
    populateItems()
    populateFooter()

    updateStatusItemEnabledness()
  }

  private func populateHeader() {
    let headerItem = NSMenuItem()
    headerItem.title = "Maccy"
    headerItem.view = MenuHeader().view

    menu.insertItem(headerItem, at: 0)
  }

  private func updateHeader() {
    menu.removeItem(at: 0)
    populateHeader()
  }

  private func populateItems() {
    menu.buildItems()
    menu.updateUnpinnedItemsVisibility()
    updateMenuTitle()
  }

  private func populateFooter() {
    MenuFooter.allCases.map({ $0.menuItem }).forEach({ item in
      item.action = #selector(menuItemAction)
      item.target = self
      menu.addItem(item)
    })
  }

  private func updateFooter() {
    MenuFooter.allCases.forEach({ _ in
      menu.removeItem(at: menu.numberOfItems - 1)
    })
    populateFooter()
  }

  @objc
  private func menuItemAction(_ sender: NSMenuItem) {
    if let tag = MenuFooter(rawValue: sender.tag) {
      switch tag {
      case .about:
        Maccy.returnFocusToPreviousApp = false
        about.openAbout(sender)
        Maccy.returnFocusToPreviousApp = true
      case .clear:
        clearUnpinned()
      case .clearAll:
        clearAll()
      case .quit:
        NSApp.terminate(sender)
      case .preferences:
        Maccy.returnFocusToPreviousApp = false
        settingsWindowController.show()
        settingsWindowController.window?.orderFrontRegardless()
        Maccy.returnFocusToPreviousApp = true
      default:
        break
      }
    }
  }

  private func clearAll(suppressClearAlert: Bool = false) {
    withClearAlert(suppressClearAlert: suppressClearAlert) {
      self.history.clear()
      self.menu.clearAll()
      self.clipboard.clear()
      self.updateMenuTitle()
    }
  }

  private func withClearAlert(suppressClearAlert: Bool, _ closure: @escaping () -> Void) {
    if suppressClearAlert || UserDefaults.standard.suppressClearAlert {
      closure()
    } else {
      Maccy.returnFocusToPreviousApp = false
      let alert = clearAlert
      DispatchQueue.main.async {
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
          if alert.suppressionButton?.state == .on {
            UserDefaults.standard.suppressClearAlert = true
          }
          closure()
        }
        Maccy.returnFocusToPreviousApp = true
      }
    }
  }

  private func rebuild() {
    menu.clearAll()
    menu.removeAllItems()

    populateHeader()
    populateItems()
    populateFooter()
  }

  private func updateMenuTitle(_ item: HistoryItem? = nil) {
    guard UserDefaults.standard.showRecentCopyInMenuBar else {
      statusItem.button?.title = ""
      return
    }

    var title = ""
    if let item = item {
      title = HistoryMenuItem(item: item, clipboard: clipboard).title
    } else if let item = menu.firstUnpinnedHistoryMenuItem {
      title = item.title
    }

    statusItem.button?.title = String(title.prefix(statusItemTitleMaxLength))
  }

  private func updateStatusMenuIcon(_ newIcon: String) {
    guard let button = statusItem.button else {
      return
    }

    switch newIcon {
    case "scissors":
      button.image = NSImage(named: .scissors)
    case "paperclip":
      button.image = NSImage(named: .paperclip)
    case "clipboard":
      button.image = NSImage(named: .clipboard)
    default:
      button.image = NSImage(named: .maccyStatusBar)
    }
    button.imagePosition = .imageRight
    (button.cell as? NSButtonCell)?.highlightsBy = []
  }

  private func updateStatusItemEnabledness() {
    statusItem.button?.appearsDisabled = UserDefaults.standard.ignoreEvents ||
      UserDefaults.standard.enabledPasteboardTypes.isEmpty
  }

  // swiftlint:disable function_body_length
  private func initializeObservers() {
    clipboardCheckIntervalObserver = UserDefaults.standard.observe(\.clipboardCheckInterval, options: .new) { _, _ in
      self.clipboard.restart()
    }
    enabledPasteboardTypesObserver = UserDefaults.standard.observe(\.enabledPasteboardTypes, options: .new) { _, _ in
      self.updateStatusItemEnabledness()
    }
    ignoreEventsObserver = UserDefaults.standard.observe(\.ignoreEvents, options: .new) { _, _ in
      self.updateStatusItemEnabledness()
    }
    imageHeightObserver = UserDefaults.standard.observe(\.imageMaxHeight, options: .new) { _, _ in
      self.menu.resizeImageMenuItems()
    }
    maxMenuItemLengthObserver = UserDefaults.standard.observe(\.maxMenuItemLength, options: .new) { _, _ in
      self.menu.regenerateMenuItemTitles()
      CoreDataManager.shared.saveContext()
    }
    hideFooterObserver = UserDefaults.standard.observe(\.hideFooter, options: .new) { _, _ in
      self.updateFooter()
    }
    hideSearchObserver = UserDefaults.standard.observe(\.hideSearch, options: .new) { _, _ in
      self.updateHeader()
    }
    hideTitleObserver = UserDefaults.standard.observe(\.hideTitle, options: .new) { _, _ in
      self.updateHeader()
    }
    pasteByDefaultObserver = UserDefaults.standard.observe(\.pasteByDefault, options: .new) { _, _ in
      self.rebuild()
    }
    pinToObserver = UserDefaults.standard.observe(\.pinTo, options: .new) { _, _ in
      self.rebuild()
    }
    removeFormattingByDefaultObserver = UserDefaults.standard.observe(\.removeFormattingByDefault,
                                                                      options: .new) { _, _ in
      self.rebuild()
    }
    sortByObserver = UserDefaults.standard.observe(\.sortBy, options: .new) { _, _ in
      self.rebuild()
    }
    showSpecialSymbolsObserver = UserDefaults.standard.observe(\.showSpecialSymbols, options: .new) { _, _ in
      self.menu.regenerateMenuItemTitles()
      CoreDataManager.shared.saveContext()
    }
    showRecentCopyInMenuBarObserver = UserDefaults.standard.observe(\.showRecentCopyInMenuBar,
                                                                    options: .new) { _, _ in
      self.updateMenuTitle()
    }
    statusItemConfigurationObserver = UserDefaults.standard.observe(\.showInStatusBar,
                                                                    options: .new) { _, change in
      if self.statusItem.isVisible != change.newValue! {
        self.statusItem.isVisible = change.newValue!
      }
    }
    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if UserDefaults.standard.showInStatusBar != change.newValue! {
        UserDefaults.standard.showInStatusBar = change.newValue!
      }
    }
    statusItemChangeObserver = UserDefaults.standard.observe(\.menuIcon, options: .new) { _, change in
      self.updateStatusMenuIcon(change.newValue!)
    }
  }
  // swiftlint:enable function_body_length

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin]
    names.forEach(KeyboardShortcuts.disable)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
}
// swiftlint:enable type_body_length
