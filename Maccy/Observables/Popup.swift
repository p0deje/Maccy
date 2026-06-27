import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

enum PopupState {
  // Default; shortcut will toggle the popup
  case toggle
  // In this mode, every additional press of the main key
  // will cycle to the next item in the paste history list.
  // Releasing the modifier keys will accept selection and close the popup
  case cycle
  // Transition state when the shortcut is first pressed and
  // we don't know whether we are in "toggle" or "cycle" mode.
  case opening
}

@MainActor
@Observable
class Popup {
  static let verticalSeparatorPadding = 6.0
  static let horizontalSeparatorPadding = 6.0
  static let verticalPadding: CGFloat = 5
  static let horizontalPadding: CGFloat = 5
  static let minimumPreviewHeight: CGFloat = 150

  // Radius used for items inset by the padding. Ensures they visually have the same curvature
  // as the menu.
  static let cornerRadius: CGFloat = if #available(macOS 26.0, *) {
    7
  } else {
    4
  }

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

  nonisolated(unsafe) private var eventsMonitor: Any?

  private var state: PopupState = .toggle

  init() {
    KeyboardShortcuts.onKeyDown(for: .popup, action: handleFirstKeyDown)
    initEventsMonitor()
  }

  deinit {
    deinitEventsMonitor()
  }

  func initEventsMonitor() {
    guard eventsMonitor == nil else { return }

    self.eventsMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.flagsChanged, .keyDown],
      handler: handleEvent
    )
  }

  nonisolated func deinitEventsMonitor() {
    guard let eventsMonitor else { return }

    NSEvent.removeMonitor(eventsMonitor)
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.navigator.select(
      item: AppState.shared.history.unpinnedItems.first ?? AppState.shared.history.pinnedItems.first
    )
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  func reset() {
    state = .toggle
    // BS-6.13: the global `.popup` hotkey is registered once in `init` and stays
    // registered for the process lifetime. We no longer `enable(.popup)` here (and
    // no longer `disable(.popup)` in `handleFirstKeyDown`) on every open/close —
    // `KeyboardShortcuts.enable`→`register` calls `RegisterEventHotKey` with a new
    // id each time, and the ~58KB Carbon backing is not reclaimed by
    // `UnregisterEventHotKey`, leaking per cycle (783 / 43.5MB over ~2 days; see
    // docs/audit/2026-06-24/00-memory-profile.md §2). In-popup hotkey presses are
    // now routed through the always-on global `handleFirstKeyDown` (the Carbon
    // handler returns `noErr`, consuming the event, so it never reaches the local
    // `eventsMonitor`), preserving cycle/select/toggle-close behavior.
  }

  func close() {
    AppState.shared.appDelegate?.panel.close()  // close() calls reset
  }

  func isClosed() -> Bool {
    AppState.shared.appDelegate?.panel.isPresented != true
  }

  func preferredHeight(for newHeight: CGFloat) -> CGFloat {
    var height = newHeight

    var minimumHeight = 0.0
    // If the preview is non-empty make sure the window accomodates for it to be visible.
    if AppState.shared.preview.state.isOpen && AppState.shared.navigator.leadSelection != nil {
      minimumHeight += Self.minimumPreviewHeight
    }
    minimumHeight = max(headerHeight + Self.verticalPadding, minimumHeight)

    height = max(height, minimumHeight)
    height = min(height, Defaults[.windowSize].height)
    return height
  }

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

  private func handleFirstKeyDown() {
    if isClosed() {
      // BS-4.7: warm the history before opening so the data is ready (or loading)
      // when the popup appears. No-op if already loaded.
      AppState.shared.prewarmVisibleWindow()
      open(height: height)
      state = .opening
      // BS-6.13: previously `KeyboardShortcuts.disable(.popup)` (re-enabled in
      // `reset()` on close) so the local `eventsMonitor` owned in-popup hotkey
      // presses. That enable/disable cycle leaked a Carbon `EventHotKeyRef` per
      // open/close. The global hotkey now stays registered: the Carbon handler
      // consumes the event (returns `noErr`), so while the popup is open the
      // hotkey press is dispatched here — not to the local monitor — and we route
      // it to `handleRepeatedHotKeyDown` for the same cycle/select/toggle-close
      // behavior the local monitor used to perform.
      return
    }

    // Popup is open and the hotkey was pressed. Route to the in-popup behavior the
    // local `eventsMonitor` used to own (cycle / select-pressed-shortcut /
    // toggle-close). The Carbon global hotkey only fires when the full
    // key+modifiers match, so the `state == .toggle` toggle-close path applies.
    _ = handleRepeatedHotKeyDown()
  }

  #if DEBUG
  func handleTestingHotKeyDown() {
    if isClosed() || state == .toggle {
      handleFirstKeyDown()
    } else {
      _ = handleRepeatedHotKeyDown()
    }
  }

  func handleTestingModifiersReleased() {
    _ = handleAllModifiersReleased()
  }
  #endif

  private func handleEvent(_ event: NSEvent) -> NSEvent? {
    switch event.type {
    case .keyDown:
      return handleKeyDown(event)
    case .flagsChanged:
      return handleFlagsChanged(event)
    default:
      return event
    }
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    // BS-6.13: the global `.popup` Carbon hotkey consumes its keyDown (returns
    // `noErr`), so the hotkey never reaches this local monitor — in-popup hotkey
    // behavior is routed via `handleFirstKeyDown`. Pass non-hotkey events through
    // so normal navigation (arrows, number shortcuts, etc.) is unaffected.
    return event
  }

  private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
    // If we are in cycle mode, releasing modifiers triggers a selection
    if state == .cycle && allModifiersReleased(event) {
      return handleAllModifiersReleased(event)
    }

    // Otherwise if in opening mode, enter toggle mode
    if state == .opening && allModifiersReleased(event) {
      state = .toggle
      return event
    }

    return event
  }

  private func allModifiersReleased(_ event: NSEvent) -> Bool {
    return event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask)
  }

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
