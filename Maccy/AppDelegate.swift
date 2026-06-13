import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
  var panel: FloatingPanel<ContentView>!

  #if DEBUG
  private enum UITestNotification {
    static let hotKeyDown = Notification.Name("org.p0deje.Maccy.UITest.hotKeyDown")
    static let modifiersReleased = Notification.Name("org.p0deje.Maccy.UITest.modifiersReleased")
    static let clearHistory = Notification.Name("org.p0deje.Maccy.UITest.clearHistory")
    static let clearAllHistory = Notification.Name("org.p0deje.Maccy.UITest.clearAllHistory")
    static let pinHistoryItem = Notification.Name("org.p0deje.Maccy.UITest.pinHistoryItem")
  }

  private var uiTestNotificationObservers: [Any] = []
  #endif

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.behavior = .removalAllowed
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.image = Defaults[.menuIcon].image
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    return statusItem
  }()

  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      SPUUpdater(hostBundle: Bundle.main,
                 applicationBundle: Bundle.main,
                 userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
                 delegate: nil)
      .automaticallyChecksForUpdates = false
    }
    #endif

    // Bridge FloatingPanel via AppDelegate.
    AppState.shared.appDelegate = self

    Clipboard.shared.onNewCopy { History.shared.add($0) }
    Clipboard.shared.start()

    Task {
      for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
        Clipboard.shared.restart()
      }
    }

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, Defaults[.showInStatusBar] != newValue {
        Defaults[.showInStatusBar] = newValue
      }
    }

    Task {
      for await value in Defaults.updates(.showInStatusBar) {
        statusItem.isVisible = value
      }
    }

    Task {
      for await value in Defaults.updates(.menuIcon, initial: false) {
        statusItem.button?.image = value.image
      }
    }

    synchronizeMenuIconText()
    Task {
      for await value in Defaults.updates(.showRecentCopyInMenuBar) {
        if value {
          statusItem.button?.title = AppState.shared.menuIconText
        } else {
          statusItem.button?.title = ""
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.ignoreEvents) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }

    Task {
      for await _ in Defaults.updates(.enabledPasteboardTypes) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    migrateUserDefaults()
    disableUnusedGlobalHotkeys()

    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      ContentView()
    }

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      Defaults[.suppressClearAlert] = true
      installUITestNotificationHooks()
    }
    #endif
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    #if DEBUG
    removeUITestNotificationHooks()
    #endif

    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  private func migrateUserDefaults() {
    if Defaults[.migrations]["2024-07-01-version-2"] != true {
      // Start 2.x from scratch.
      Defaults.reset(.migrations)

      // Inverse hide* configuration keys.
      Defaults[.showFooter] = !UserDefaults.standard.bool(forKey: "hideFooter")
      Defaults[.showSearch] = !UserDefaults.standard.bool(forKey: "hideSearch")
      Defaults[.showTitle] = !UserDefaults.standard.bool(forKey: "hideTitle")
      UserDefaults.standard.removeObject(forKey: "hideFooter")
      UserDefaults.standard.removeObject(forKey: "hideSearch")
      UserDefaults.standard.removeObject(forKey: "hideTitle")

      Defaults[.migrations]["2024-07-01-version-2"] = true
    }

    // The following defaults are not used in Maccy 2.x
    // and should be removed in 3.x.
    // - LaunchAtLogin__hasMigrated
    // - avoidTakingFocus
    // - saratovSeparator
    // - maxMenuItemLength
    // - maxMenuItems
  }

  @objc
  private func performStatusItemClick() {
    if let event = NSApp.currentEvent {
      let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

      if modifierFlags.contains(.option) {
        Defaults[.ignoreEvents].toggle()

        if modifierFlags.contains(.shift) {
          Defaults[.ignoreOnlyNextEvent] = Defaults[.ignoreEvents]
        }

        return
      }
    }

    panel.toggle(height: AppState.shared.popup.height, at: .statusItem)
  }

  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else {
          return
        }
        if Defaults[.showRecentCopyInMenuBar] {
          self.statusItem.button?.title = AppState.shared.menuIconText
        }
        self.synchronizeMenuIconText()
      }
    }
  }

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

  #if DEBUG
  private func installUITestNotificationHooks() {
    guard uiTestNotificationObservers.isEmpty else {
      return
    }

    let center = DistributedNotificationCenter.default()
    uiTestNotificationObservers.append(
      center.addObserver(forName: UITestNotification.hotKeyDown, object: nil, queue: .main) { _ in
        Task { @MainActor in
          AppState.shared.popup.handleTestingHotKeyDown()
        }
      }
    )
    uiTestNotificationObservers.append(
      center.addObserver(forName: UITestNotification.modifiersReleased, object: nil, queue: .main) { _ in
        Task { @MainActor in
          AppState.shared.popup.handleTestingModifiersReleased()
        }
      }
    )
    uiTestNotificationObservers.append(
      center.addObserver(forName: UITestNotification.clearHistory, object: nil, queue: .main) { _ in
        Task { @MainActor in
          AppState.shared.history.clear()
        }
      }
    )
    uiTestNotificationObservers.append(
      center.addObserver(forName: UITestNotification.clearAllHistory, object: nil, queue: .main) { _ in
        Task { @MainActor in
          AppState.shared.history.clearAll()
        }
      }
    )
    uiTestNotificationObservers.append(
      center.addObserver(forName: UITestNotification.pinHistoryItem, object: nil, queue: .main) { notification in
        Task { @MainActor in
          guard let title = notification.userInfo?["title"] as? String else {
            return
          }

          let item = AppState.shared.history.all.first { $0.title == title }
          AppState.shared.history.togglePin(item)
        }
      }
    )
  }

  private func removeUITestNotificationHooks() {
    let center = DistributedNotificationCenter.default()
    uiTestNotificationObservers.forEach { center.removeObserver($0) }
    uiTestNotificationObservers = []
  }
  #endif
}
