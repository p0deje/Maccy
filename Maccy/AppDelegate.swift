import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
  var panel: FloatingPanel<ContentView>!
  var todosPanel: FloatingPanel<TodosWindowView>!

  /// Returns the window hosting the given tab — prefers the main popup when it is open.
  func floatingPanel(for tab: AppTab) -> NSWindow? {
    switch tab {
    case .clipboard:
      return panel
    case .todos:
      if panel.isPresented {
        return panel
      }
      return todosPanel
    }
  }

  func verticallyResizePresentedPanel(to height: CGFloat) {
    if panel.isPresented {
      panel.verticallyResize(to: height)
    } else if todosPanel.isPresented {
      todosPanel.verticallyResize(to: height)
    }
  }

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
    observeFocusedApplications()

    Task { @MainActor in
      try? await History.shared.load()
      try? Todos.shared.load()
      ReminderScheduler.shared.rescheduleAll()
    }

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
    Notifier.register()
    ReminderScheduler.shared.register()
    UNUserNotificationCenter.current().delegate = self
    disableUnusedGlobalHotkeys()
    QuickPaste.shared.register()
    registerTodosShortcut()

    if let tab = AppTab(rawValue: Defaults[.defaultAppTab]) {
      AppState.shared.activeTab = tab
    }

    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      ContentView()
    }

    todosPanel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: "org.p0deje.Maccy.todos",
      onClose: {}
    ) {
      TodosWindowView()
    }

    if Defaults[.openTodosWindowAtLaunch] {
      openTodosWindow()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  @objc
  func openTodosWindow() {
    AppState.shared.activeTab = .todos
    todosPanel.toggle(height: AppState.shared.popup.height)
  }

  private func registerTodosShortcut() {
    KeyboardShortcuts.onKeyUp(for: .openTodos) { [weak self] in
      self?.openTodosWindow()
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
      if event.type == .rightMouseUp {
        showStatusItemMenu(at: event)
        return
      }

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

  private func showStatusItemMenu(at event: NSEvent) {
    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(
        title: NSLocalizedString("ClipboardTab", tableName: "Todos", comment: ""),
        action: #selector(openClipboardFromMenu),
        keyEquivalent: ""
      )
    )
    menu.addItem(
      NSMenuItem(
        title: NSLocalizedString("TodosTab", tableName: "Todos", comment: "") + "…",
        action: #selector(openTodosFromMenu),
        keyEquivalent: ""
      )
    )
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
        action: #selector(openPreferencesFromMenu),
        keyEquivalent: ","
      )
    )
    menu.items.forEach { $0.target = self }
    if let button = statusItem.button {
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
  }

  @objc
  private func openClipboardFromMenu() {
    AppState.shared.activeTab = .clipboard
    panel.toggle(height: AppState.shared.popup.height, at: .statusItem)
  }

  @objc
  private func openTodosFromMenu() {
    openTodosWindow()
  }

  @objc
  private func openPreferencesFromMenu() {
    Task { @MainActor in
      AppState.shared.openPreferences()
    }
  }

  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: {
      DispatchQueue.main.async {
        if Defaults[.showRecentCopyInMenuBar] {
          self.statusItem.button?.title = AppState.shared.menuIconText
        }
        self.synchronizeMenuIconText()
      }
    }
  }

  private func observeFocusedApplications() {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { notification in
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
        return
      }

      Clipboard.shared.noteActivatedApplication(app)
    }

    if let app = NSWorkspace.shared.frontmostApplication {
      Clipboard.shared.noteActivatedApplication(app)
    }
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin, .quickPasteBase]
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

extension AppDelegate: UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    await MainActor.run {
      ReminderScheduler.shared.handleNotificationResponse(response)
    }
  }
}
