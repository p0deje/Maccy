import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

enum PopupState {
  /// Default; shortcut will toggle the popup
  case toggle
  /// In this mode, every additional press of the main key will cycle to the next item in the paste history list.
  ///  Releasing the modifier keys will accept selection and close the popup
  case cycle
  /// Transition state when the shortcut is first pressed and we don't know whether we are in "toggle" or "cycle" mode.
  case opening
}

@Observable
class Popup {
  let verticalPadding: CGFloat = 5

  var needsResize = false
  var height: CGFloat = 0
  var headerHeight: CGFloat = 0
  var pinnedItemsHeight: CGFloat = 0
  var footerHeight: CGFloat = 0

  private var eventsMonitor: Any?

  private var state: PopupState = .toggle

  init() {
    KeyboardShortcuts.onKeyDown(for: .popup, action: handleFirstKeyDown)
    initEventsMonitor()
  }

  deinit {
    deinitEventsMonitor()
  }

  func initEventsMonitor() {
    if eventsMonitor != nil { return }
    eventsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handleEvent)
  }

  func deinitEventsMonitor() {
    guard let monitor = eventsMonitor else { return }
    NSEvent.removeMonitor(monitor)
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  func reset() {
    state = .toggle
    KeyboardShortcuts.enable(.popup)
  }

  func close() {
    AppState.shared.appDelegate?.panel.close()  // close() calls reset
  }

  func isClosed() -> Bool {
    AppState.shared.appDelegate?.panel.isPresented != true
  }

  func resize(height: CGFloat) {
    self.height = height + headerHeight + pinnedItemsHeight + footerHeight + (verticalPadding * 2)
    AppState.shared.appDelegate?.panel.verticallyResize(to: self.height)
    needsResize = false
  }

  private func handleFirstKeyDown() {

    if isClosed() {
      open(height: height)
      state = .opening
      KeyboardShortcuts.disable(.popup)  // Handle events via eventsMonitor. Re-enable on popup close
      return
    }

    // Maccy was not opened via shortcut. We assume toggle mode and close it
    close()
  }

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

    // Ensure the event is related to the shortcut
    if allModifiersReleased(event) || isNotKey(event) {
      return event
    }

    if state == .opening {
      state = .cycle
      // Next 'if' will highlight next item and then return nil
    }

    if state == .cycle {
      AppState.shared.highlightNext(allowCycle: true)
      return nil
    }

    if state == .toggle && allModifiersPressed(event) {
      close()
      return nil
    }

    return event
  }

  private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {

    // If we are in cycle mode, releasing modifiers triggers a selection
    if state == .cycle && allModifiersReleased(event) {
      DispatchQueue.main.async {
        AppState.shared.select()
      }
      return nil
    }

    // Otherwise if in opening mode, enter toggle mode
    if state == .opening && allModifiersReleased(event) {
      state = .toggle
      return nil
    }

    return event
  }
}

private func isNotKey(_ event: NSEvent) -> Bool {
  guard let rawValue = KeyboardShortcuts.Name.popup.shortcut?.key?.rawValue else {
    return true
  }

  return rawValue != event.keyCode
}

private func allModifiersReleased(_ event: NSEvent) -> Bool {
  guard let shortcut = KeyboardShortcuts.Name.popup.shortcut else {
    return false
  }

  return event.modifierFlags.isDisjoint(with: shortcut.modifiers)
}

private func allModifiersPressed(_ event: NSEvent) -> Bool {
    guard let shortcut = KeyboardShortcuts.Name.popup.shortcut else {
        return false
    }

    return event.modifierFlags.isSuperset(of: shortcut.modifiers)
}
