import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

/// Application delegate: wires the pasteboard observer, ingest actor, status
/// item, floating panel, and memory governor at launch.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
  /// The main floating panel hosting the content view.
  var panel: FloatingPanel<ContentView>!

  #if DEBUG
  /// Distributed-notification names driven by UI tests (test process → app).
  private enum UITestNotification {
    static let hotKeyDown = Notification.Name("org.p0deje.Maccy.UITest.hotKeyDown")
    static let modifiersReleased = Notification.Name("org.p0deje.Maccy.UITest.modifiersReleased")
    static let clearHistory = Notification.Name("org.p0deje.Maccy.UITest.clearHistory")
    static let clearAllHistory = Notification.Name("org.p0deje.Maccy.UITest.clearAllHistory")
    static let pinHistoryItem = Notification.Name("org.p0deje.Maccy.UITest.pinHistoryItem")
  }

  /// Distributed-notification names driving the performance benchmarks (see
  /// `PerfRecorder`). Posted by the UI test process; observed here only when
  /// launched with `MaccyPerfRecord`.
  private enum PerfNotification {
    static let reset = Notification.Name("org.p0deje.Maccy.Perf.reset")
    static let dump = Notification.Name("org.p0deje.Maccy.Perf.dump")
    static let openPreview = Notification.Name("org.p0deje.Maccy.Perf.openPreview")
    static let bulkLoad = Notification.Name("org.p0deje.Maccy.Perf.bulkLoad")
  }

  private var uiTestNotificationObservers: [Any] = []
  private var perfNotificationObservers: [Any] = []
  #endif

  /// The menu-bar status item, configured from user defaults.
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

  /// True when the status item should appear disabled (events ignored or no
  /// enabled types).
  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?

  /// Early launch hook: disables Sparkle auto-update under testing, bridges the
  /// panel, wires the ingest actor, and starts the pasteboard observer.
  func applicationWillFinishLaunching(_ notification: Notification) {
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

    // Wire the off-main ingest actor: the pasteboard snapshot is
    // filtered/deduped/written on a background SwiftData context, and the
    // resulting `StoreEvent` hops back to the main actor to reconcile the
    // main-context history. `Clipboard.checkForChangesInPasteboard` dispatches
    // each copy to this actor via `Task { ... }`.
    //
    // The same image processor instance backs the decorators' default
    // processor, so thumbnails decoded during ingest are reused when the item
    // is rendered — one thumbnail cache across the ingest + view paths.
    Clipboard.shared.ingestor = BackgroundClipboardIngestor(
      modelContainer: Storage.shared.container,
      image: HistoryItemDecorator.defaultImageProcessor,
      now: { Date() },
      onEvent: { @MainActor event in History.shared.consume(event) }
    )
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

  /// Late launch hook: migrates defaults, builds the floating panel, attaches
  /// the memory governor, and installs test/perf hooks under DEBUG.
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

    // Wire the memory governor — reclaim non-viewport image bitmaps + caches on
    // `NSApplication.didReceiveMemoryWarningNotification`.
    MainActor.assumeIsolated {
      MemoryGovernor.shared.attach(history: History.shared)
      MemoryGovernor.shared.start()
    }

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      Defaults[.suppressClearAlert] = true
      installUITestNotificationHooks()
    }
    if CommandLine.arguments.contains("MaccyPerfRecord") {
      installPerfNotificationHooks()
    }
    #endif
  }

  /// Reopens (toggles) the panel when the dock icon is clicked.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  /// Termination hook: dumps any perf recording, clears history on quit if set.
  func applicationWillTerminate(_ notification: Notification) {
    #if DEBUG
    removeUITestNotificationHooks()
    if CommandLine.arguments.contains("MaccyPerfRecord") {
      // Fallback dump so a forgotten `MaccyPerfDump` still lands the recorded
      // events. Safe no-op when nothing was recorded or the log path is unset.
      MainActor.assumeIsolated {
        PerfRecorder.shared.dump(category: "terminate")
      }
      removePerfNotificationHooks()
    }
    #endif

    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  /// Migrates legacy user-default keys from Maccy 1.x to the 2.x schema.
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

  /// Status-item click handler: toggles ignore-events on option-click,
  /// otherwise toggles the panel.
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

  /// Keeps the status item title in sync with the recent-copy text via
  /// observation tracking.
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

  /// Disables the unused built-in delete/pin global shortcuts and keeps them
  /// disabled if reassigned.
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
  /// Registers the distributed-notification observers that drive UI tests.
  private func installUITestNotificationHooks() {
    guard uiTestNotificationObservers.isEmpty else {
      return
    }

    let center = DistributedNotificationCenter.default()
    uiTestNotificationObservers.append(
      center.addObserver(forName: UITestNotification.hotKeyDown, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated {
          AppState.shared.popup.handleTestingHotKeyDown()
        }
      }
    )
    uiTestNotificationObservers.append(
      center.addObserver(forName: UITestNotification.modifiersReleased, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated {
          AppState.shared.popup.handleTestingModifiersReleased()
        }
      }
    )
    uiTestNotificationObservers.append(
      center.addObserver(forName: UITestNotification.clearHistory, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated {
          AppState.shared.history.clear()
        }
      }
    )
    uiTestNotificationObservers.append(
      center.addObserver(forName: UITestNotification.clearAllHistory, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated {
          AppState.shared.history.clearAll()
        }
      }
    )
    uiTestNotificationObservers.append(
      center.addObserver(forName: UITestNotification.pinHistoryItem, object: nil, queue: .main) { notification in
        // Extract Sendable values BEFORE the @MainActor block so the non-Sendable
        // `notification` is not sent across isolation. The observer fires on
        // .main; assumeIsolated is a synchronous no-op assertion.
        let title = notification.userInfo?["title"] as? String
        MainActor.assumeIsolated {
          guard let title else {
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

  /// Registers the perf-benchmark notification observers (only when launched
  /// with `MaccyPerfRecord`). Mirrors `installUITestNotificationHooks`: the UI
  /// test drives the benchmarks over the distributed-notification bridge.
  private func installPerfNotificationHooks() {
    guard perfNotificationObservers.isEmpty else {
      return
    }

    let center = DistributedNotificationCenter.default()
    perfNotificationObservers.append(
      center.addObserver(forName: PerfNotification.reset, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated {
          PerfRecorder.shared.reset()
        }
      }
    )
    perfNotificationObservers.append(
      center.addObserver(forName: PerfNotification.dump, object: nil, queue: .main) { notification in
        let category = notification.userInfo?["category"] as? String ?? "unknown"
        MainActor.assumeIsolated {
          PerfRecorder.shared.dump(category: category)
        }
      }
    )
    perfNotificationObservers.append(
      center.addObserver(forName: PerfNotification.openPreview, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated {
          // Opens the preview pane deterministically (avoids the flaky
          // control+space keyboard toggle on the headless runner). Lead item is
          // already selected on popup open, so `togglePreview` will open.
          AppState.shared.preview.togglePreview()
        }
      }
    )
    perfNotificationObservers.append(
      center.addObserver(forName: PerfNotification.bulkLoad, object: nil, queue: .main) { notification in
        let count = notification.userInfo?["count"] as? Int ?? 0
        let category = notification.userInfo?["category"] as? String ?? "image"
        MainActor.assumeIsolated {
          PerfFixtures.populate(count: count, category: category)
        }
      }
    )
  }

  /// Removes the perf-benchmark notification observers.
  private func removePerfNotificationHooks() {
    let center = DistributedNotificationCenter.default()
    perfNotificationObservers.forEach { center.removeObserver($0) }
    perfNotificationObservers = []
  }
  #endif
}
