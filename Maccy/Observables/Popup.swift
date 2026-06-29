import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

/// The popup's high-level behavior mode, driven by the hotkey press sequence.
enum PopupState {
  /// Default; the hotkey toggles the popup open/closed.
  case toggle
  /// Each additional press of the main key cycles to the next item; releasing
  /// the modifier keys accepts the selection and closes the popup.
  case cycle
  /// Transition state when the shortcut is first pressed and the mode
  /// (toggle vs cycle) is not yet determined.
  case opening
}

/// Observable model for the popup window: geometry constants, the events
/// monitor, the toggle/cycle state machine, and the hotkey handlers.
@MainActor
@Observable
class Popup {
  static let verticalSeparatorPadding = 6.0
  static let horizontalSeparatorPadding = 6.0
  static let verticalPadding: CGFloat = 5
  static let horizontalPadding: CGFloat = 5
  static let minimumPreviewHeight: CGFloat = 150

  /// Radius for items inset by the padding, so they visually share the menu's curvature.
  static let cornerRadius: CGFloat = if #available(macOS 26.0, *) {
    7
  } else {
    4
  }

  /// Per-row height (version-dependent).
  static let itemHeight: CGFloat = if #available(macOS 26.0, *) {
    24
  } else {
    22
  }

  /// Caps the measured scroll-content height so the popup shows at most
  /// `maxVisibleItems` rows (older items scroll into view). Returns
  /// `contentHeight` unchanged when `maxVisibleItems <= 0` (no cap). The final
  /// window height is still floor-clamped to the preview/header minimum and
  /// ceiling-clamped to the saved window height by `preferredHeight(for:)`.
  static func cappedListHeight(
    contentHeight: CGFloat,
    maxVisibleItems: Int,
    itemHeight: CGFloat
  ) -> CGFloat {
    guard maxVisibleItems > 0 else { return contentHeight }
    return min(contentHeight, CGFloat(maxVisibleItems) * itemHeight)
  }

  var needsResize = false
  var height: CGFloat = 0
  var headerHeight: CGFloat = 0
  var extraTopHeight: CGFloat = 0
  var extraBottomHeight: CGFloat = 0
  var footerHeight: CGFloat = 0

  // The `NSEvent` local-monitor token (opaque `Any`). Added on main in
  // `initEventsMonitor`, removed in `deinitEventsMonitor`. The token never leaves
  // the main actor (added/removed/fired on main), so it is a plain `@MainActor`
  // instance var — no lock, no `@unchecked`, no `nonisolated(unsafe)`. The
  // nonisolated deinit reaches it via `MainActor.assumeIsolated`, a synchronous
  // runtime assertion (not an async hop) — safe on macOS 14 (no SE-0371 hop).
  private var eventsMonitor: Any?

  private var state: PopupState = .toggle

  /// Registers the global `.popup` hotkey and the local events monitor.
  init() {
    KeyboardShortcuts.onKeyDown(for: .popup, action: handleFirstKeyDown)
    initEventsMonitor()
  }

  /// Removes the events monitor.
  deinit {
    deinitEventsMonitor()
  }

  /// Installs the local `flagsChanged`/`keyDown` monitor (no-op if installed).
  func initEventsMonitor() {
    guard eventsMonitor == nil else { return }
    eventsMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.flagsChanged, .keyDown]
    ) { event in
      // Local NSEvent monitors fire on the main run loop, so this nonisolated
      // closure runs on main and MainActor.assumeIsolated is a runtime no-op
      // assertion. NSEvent is NOT Sendable, so it must not cross the isolation
      // boundary — extract Sendable properties (type / all-released Bool) on
      // this side, decide on main via assumeIsolated, and return nil/event
      // here without ever moving `event` across actors. No @unchecked, no
      // nonisolated(unsafe).
      switch event.type {
      case .flagsChanged:
        let allReleased = event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask)
        let consume = MainActor.assumeIsolated {
          AppState.shared.popup.shouldConsumeFlagsChanged(allReleased: allReleased)
        }
        return consume ? nil : event
      case .keyDown:
        // The global `.popup` Carbon hotkey consumes its keyDown, so in-popup
        // hotkey behavior is routed via `handleFirstKeyDown`; pass non-hotkey
        // keyDowns through unchanged.
        return event
      default:
        return event
      }
    }
  }

  /// Removes the events monitor from this nonisolated deinit.
  nonisolated func deinitEventsMonitor() {
    // `removeMonitor` is thread-safe (AppKit docs). The token is main-isolated;
    // reach it from this nonisolated deinit via `MainActor.assumeIsolated` — a
    // synchronous runtime assertion, NOT an async hop, so the macOS-14 "deinit
    // cannot actor-hop" restriction does not apply. `Popup` is a
    // process-lifetime singleton (`AppState.shared.popup`), so deinit
    // effectively never fires in prod — but the no-unsafe isolation must be
    // correct regardless.
    MainActor.assumeIsolated {
      if let monitor = eventsMonitor {
        eventsMonitor = nil
        NSEvent.removeMonitor(monitor)
      }
    }
  }

  /// Selects the first item and opens the panel at `popupPosition`.
  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.navigator.select(
      item: AppState.shared.history.unpinnedItems.first ?? AppState.shared.history.pinnedItems.first
    )
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  /// Returns the popup to its default toggle state on close.
  ///
  /// The global `.popup` hotkey is registered once in `init` and stays
  /// registered for the process lifetime; `enable(.popup)`/`disable(.popup)`
  /// are NOT toggled per open/close. That enable/disable cycle called
  /// `RegisterEventHotKey` with a new id each time, and the Carbon backing was
  /// not reclaimed by `UnregisterEventHotKey`, leaking per cycle. In-popup
  /// hotkey presses now route through the always-on global handler (the Carbon
  /// handler returns `noErr`, consuming the event so it never reaches the local
  /// monitor), preserving cycle/select/toggle-close behavior.
  func reset() {
    state = .toggle
  }

  /// Closes the panel (which calls `reset`).
  func close() {
    AppState.shared.appDelegate?.panel.close()  // close() calls reset
  }

  /// Whether the panel is currently closed.
  func isClosed() -> Bool {
    AppState.shared.appDelegate?.panel.isPresented != true
  }

  /// Floor-clamps to the preview/header minimum and ceiling-clamps to the saved
  /// window height.
  func preferredHeight(for newHeight: CGFloat) -> CGFloat {
    var height = newHeight

    var minimumHeight = 0.0
    // If the preview is open, ensure the window accommodates its minimum height.
    if AppState.shared.preview.state.isOpen && AppState.shared.navigator.leadSelection != nil {
      minimumHeight += Self.minimumPreviewHeight
    }
    minimumHeight = max(headerHeight + Self.verticalPadding, minimumHeight)

    height = max(height, minimumHeight)
    height = min(height, Defaults[.windowSize].height)
    return height
  }

  /// Resizes the panel to fit `height`, capped to `maxVisibleItems` rows.
  func resize(height: CGFloat) {
    // `height` is the full scroll-content height (all visible-unpinned rows).
    // Cap it to maxVisibleItems rows so the popup window never grows beyond N
    // rows; the ScrollView reveals the rest. Default maxVisibleItems (36) keeps
    // the content taller than the preferredHeight window-height guardrail, so
    // the shipped ~800px look is unchanged unless the user lowers the count.
    let listHeight = Self.cappedListHeight(
      contentHeight: height,
      maxVisibleItems: Defaults[.maxVisibleItems],
      itemHeight: Self.itemHeight
    )
    self.height = listHeight + headerHeight + extraTopHeight + extraBottomHeight + footerHeight
    AppState.shared.appDelegate?.panel.verticallyResize(to: preferredHeight(for: self.height))
    needsResize = false
  }

  /// Global hotkey handler. Opens the popup on a closed state (after warming the
  /// history); otherwise routes the press to the in-popup cycle/select/toggle
  /// behavior.
  private func handleFirstKeyDown() {
    if isClosed() {
      // Warm the history before opening so the data is ready (or loading) when
      // the popup appears. No-op if already loaded.
      AppState.shared.prewarmVisibleWindow()
      open(height: height)
      state = .opening
      // The global hotkey stays registered (see `reset`): the Carbon handler
      // consumes the event (returns `noErr`), so while the popup is open the
      // hotkey press is dispatched here — not to the local monitor — and we
      // route it to `handleRepeatedHotKeyDown` for the same cycle/select/
      // toggle-close behavior the local monitor used to perform.
      return
    }

    // Popup is open and the hotkey was pressed. Route to the in-popup behavior the
    // local `eventsMonitor` used to own (cycle / select-pressed-shortcut /
    // toggle-close). The Carbon global hotkey only fires when the full
    // key+modifiers match, so the `state == .toggle` toggle-close path applies.
    _ = handleRepeatedHotKeyDown()
  }

  #if DEBUG
  /// Test hook simulating a hotkey press.
  func handleTestingHotKeyDown() {
    if isClosed() || state == .toggle {
      handleFirstKeyDown()
    } else {
      _ = handleRepeatedHotKeyDown()
    }
  }

  /// Test hook simulating all modifiers released.
  func handleTestingModifiersReleased() {
    _ = handleAllModifiersReleased()
  }
  #endif

  /// Decides (on main) whether a flagsChanged event should be consumed, given
  /// whether all modifiers were released. Extracted from the old
  /// `handleFlagsChanged` so the NSEvent monitor handler can pass only a Sendable
  /// Bool across the isolation boundary (NSEvent itself is not Sendable).
  @MainActor
  private func shouldConsumeFlagsChanged(allReleased: Bool) -> Bool {
    // If we are in cycle mode, releasing modifiers triggers a selection
    if state == .cycle && allReleased {
      _ = handleAllModifiersReleased()
      return true
    }

    // Otherwise if in opening mode, enter toggle mode
    if state == .opening && allReleased {
      state = .toggle
      return false
    }

    return false
  }

  /// Handles a repeated hotkey press while open: select a pressed-shortcut
  /// item, cycle to the next item, or toggle-close.
  private func handleRepeatedHotKeyDown(_ event: NSEvent? = nil) -> NSEvent? {
    if let item = History.shared.pressedShortcutItem {
      AppState.shared.navigator.select(item: item)
      Task { @MainActor in
        AppState.shared.history.select(item)
      }
      return nil
    }

    if state == .opening {
      state = .cycle
      // Next 'if' will highlight next item and then return nil.
    }

    if state == .cycle {
      AppState.shared.navigator.highlightNext(allowCycle: true)
      return nil
    }

    if state == .toggle {
      close()
      return nil
    }

    return event
  }

  /// Handles all-modifiers-released: accept the cycle selection, or settle an
  /// opening state back to toggle.
  private func handleAllModifiersReleased(_ event: NSEvent? = nil) -> NSEvent? {
    if state == .cycle {
      Task { @MainActor in
        AppState.shared.select()
      }
      return nil
    }

    if state == .opening {
      state = .toggle
    }

    return event
  }
}
