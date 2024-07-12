import Cocoa
import Defaults
import KeyboardShortcuts
import Settings

// swiftlint:disable type_body_length
class Maccy: NSObject {
  static var returnFocusToPreviousApp = true

  @objc let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  var selectedItem: HistoryItemL? { menu.lastSelectedItem?.item }

  private let statusItemTitleMaxLength = 20

  private let about = About()
  private let clipboard = Clipboard.shared
  private let history = HistoryL()
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

  private let GeneralSettingsViewController: () -> SettingsPane = {
    let paneView = Settings.Pane(
      identifier: Settings.PaneIdentifier.general,
      title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
      toolbarIcon: NSImage.gearshape!
    ) {
      GeneralSettingsPane()
    }

    return Settings.PaneHostingController(pane: paneView)
  }

  private let StorageSettingsViewController: () -> SettingsPane = {
    let paneView = Settings.Pane(
      identifier: Settings.PaneIdentifier.storage,
      title: NSLocalizedString("Title", tableName: "StorageSettings", comment: ""),
      toolbarIcon: NSImage.externaldrive!
    ) {
      StorageSettingsPane()
    }

    return Settings.PaneHostingController(pane: paneView)
  }

  private let AppearanceSettingsViewController: () -> SettingsPane = {
    let paneView = Settings.Pane(
      identifier: Settings.PaneIdentifier.appearance,
      title: NSLocalizedString("Title", tableName: "AppearanceSettings", comment: ""),
      toolbarIcon: NSImage.paintpalette!
    ) {
      AppearanceSettingsPane()
    }

    return Settings.PaneHostingController(pane: paneView)
  }

  private let IgnoreSettingsViewController: () -> SettingsPane = {
    let paneView = Settings.Pane(
      identifier: Settings.PaneIdentifier.ignore,
      title: NSLocalizedString("Title", tableName: "IgnoreSettings", comment: ""),
      toolbarIcon: NSImage.nosign!
    ) {
      IgnoreSettingsPane()
    }

    return Settings.PaneHostingController(pane: paneView)
  }

  private let AdvancedSettingsViewController: () -> SettingsPane = {
    let paneView = Settings.Pane(
      identifier: Settings.PaneIdentifier.advanced,
      title: NSLocalizedString("Title", tableName: "AdvancedSettings", comment: ""),
      toolbarIcon: NSImage.gearshape2!
    ) {
      AdvancedSettingsPane()
    }

    return Settings.PaneHostingController(pane: paneView)
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

  private var clipboardCheckIntervalObserver: Defaults.Observation?
  private var enabledPasteboardTypesObserver: Defaults.Observation?
  private var ignoreEventsObserver: Defaults.Observation?
  private var imageHeightObserver: Defaults.Observation?
  private var hideFooterObserver: Defaults.Observation?
  private var hideSearchObserver: Defaults.Observation?
  private var hideTitleObserver: Defaults.Observation?
  private var maxMenuItemLengthObserver: Defaults.Observation?
  private var pasteByDefaultObserver: Defaults.Observation?
  private var pinToObserver: Defaults.Observation?
  private var removeFormattingByDefaultObserver: Defaults.Observation?
  private var sortByObserver: Defaults.Observation?
  private var showSpecialSymbolsObserver: Defaults.Observation?
  private var showRecentCopyInMenuBarObserver: Defaults.Observation?
  private var statusItemConfigurationObserver: Defaults.Observation?
  private var statusItemVisibilityObserver: NSKeyValueObservation?
  private var statusItemChangeObserver: Defaults.Observation?

  @MainActor
  override init() {
    super.init()

    menu = Menu(history: history, clipboard: Clipboard.shared)
    menuController = MenuController(menu, statusItem)

    initializeObservers()
    disableUnusedGlobalHotkeys()

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

  func item(at position: Int) -> HistoryItemL? {
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

  @MainActor
  private func start() {
    statusItem.behavior = .removalAllowed
    statusItem.isVisible = Defaults[.showInStatusBar]

    updateStatusMenuIcon(Defaults[.menuIcon])

    clipboard.onNewCopy(history.add)
//    clipboard.onNewCopy(menu.add)
//    clipboard.onNewCopy(updateMenuTitle)
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
    if suppressClearAlert || Defaults[.suppressClearAlert] {
      closure()
    } else {
      Maccy.returnFocusToPreviousApp = false
      let alert = clearAlert
      DispatchQueue.main.async {
        if alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn {
          if alert.suppressionButton?.state == .on {
            Defaults[.suppressClearAlert] = true
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
    guard Defaults[.showRecentCopyInMenuBar] else {
      statusItem.button?.title = ""
      return
    }

    var title = ""
    if let item = item {
//      title = HistoryMenuItem(item: item, clipboard: clipboard).title
//    } else if let item = menu.firstUnpinnedHistoryMenuItem {
      title = item.title
    }

    statusItem.button?.title = String(title.prefix(statusItemTitleMaxLength))
  }

  private func updateStatusMenuIcon(_ newIcon: MenuIcon) {
    guard let button = statusItem.button else {
      return
    }

    switch newIcon {
    case .scissors:
      button.image = NSImage(named: .scissors)
    case .paperclip:
      button.image = NSImage(named: .paperclip)
    case .clipboard:
      button.image = NSImage(named: .clipboard)
    default:
      button.image = NSImage(named: .maccyStatusBar)
    }
    button.imagePosition = .imageRight
    (button.cell as? NSButtonCell)?.highlightsBy = []
  }

  private func updateStatusItemEnabledness() {
    statusItem.button?.appearsDisabled = Defaults[.ignoreEvents] ||
      Defaults[.enabledPasteboardTypes].isEmpty
  }

  // swiftlint:disable function_body_length
  private func initializeObservers() {
    clipboardCheckIntervalObserver = Defaults.observe(.clipboardCheckInterval, options: []) { _ in
      self.clipboard.restart()
    }
    enabledPasteboardTypesObserver = Defaults.observe(.enabledPasteboardTypes, options: []) { _ in
      self.updateStatusItemEnabledness()
    }
    ignoreEventsObserver = Defaults.observe(.ignoreEvents, options: []) { _ in
      self.updateStatusItemEnabledness()
    }
    imageHeightObserver = Defaults.observe(.imageMaxHeight, options: []) { _ in
      self.menu.resizeImageMenuItems()
    }
    maxMenuItemLengthObserver = Defaults.observe(.maxMenuItemLength, options: []) { _ in
      self.menu.regenerateMenuItemTitles()
      CoreDataManager.shared.saveContext()
    }
    hideFooterObserver = Defaults.observe(.showFooter, options: []) { _ in
      self.updateFooter()
    }
    hideSearchObserver = Defaults.observe(.showSearch, options: []) { _ in
      self.updateHeader()
    }
    hideTitleObserver = Defaults.observe(.showTitle, options: []) { _ in
      self.updateHeader()
    }
    pasteByDefaultObserver = Defaults.observe(.pasteByDefault, options: []) { _ in
      self.rebuild()
    }
    pinToObserver = Defaults.observe(.pinTo, options: []) { _ in
      self.rebuild()
    }
    removeFormattingByDefaultObserver = Defaults.observe(.removeFormattingByDefault, options: []) { _ in
      self.rebuild()
    }
    sortByObserver = Defaults.observe(.sortBy, options: []) { _ in
      self.rebuild()
    }
    showSpecialSymbolsObserver = Defaults.observe(.showSpecialSymbols, options: []) { _ in
      self.menu.regenerateMenuItemTitles()
      CoreDataManager.shared.saveContext()
    }
    showRecentCopyInMenuBarObserver = Defaults.observe(.showRecentCopyInMenuBar, options: []) { _ in
      self.updateMenuTitle()
    }
    statusItemConfigurationObserver = Defaults.observe(.showInStatusBar, options: []) { change in
      if self.statusItem.isVisible != change.newValue {
        self.statusItem.isVisible = change.newValue
      }
    }
    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if Defaults[.showInStatusBar] != change.newValue! {
        Defaults[.showInStatusBar] = change.newValue!
      }
    }
    statusItemChangeObserver = Defaults.observe(.menuIcon, options: []) { change in
      self.updateStatusMenuIcon(change.newValue)
    }
  }
  // swiftlint:enable function_body_length

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin]
    KeyboardShortcuts.disable(names)

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
