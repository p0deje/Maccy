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

  private var flagsMonitor: Any?

  private var state: PopupState = .toggle

  init() {
    KeyboardShortcuts.onKeyDown(for: .popup, action: handleKeyDown)
    initFlagsMonitor()
  }

  deinit {
    deinitFlagsMonitor()
   }

  func initFlagsMonitor() {
    if flagsMonitor != nil { return }
    flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged], handler: handleFlagsChanged)
  }

  func deinitFlagsMonitor() {
    guard let monitor = flagsMonitor else { return }
    NSEvent.removeMonitor(monitor)
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  func close() {
    state = .toggle  // reset
    AppState.shared.appDelegate?.panel.close()
  }

  func isClosed() -> Bool {
    AppState.shared.appDelegate?.panel.isPresented != true
  }

  func resize(height: CGFloat) {
    self.height = height + headerHeight + pinnedItemsHeight + footerHeight + (verticalPadding * 2)
    AppState.shared.appDelegate?.panel.verticallyResize(to: self.height)
    needsResize = false
  }

  private func handleKeyDown() {
    if isClosed() {
      open(height: height)
      state = .opening
      return
    }

    // Popup is open

    if state == .opening {
      state = .cycle
      // Next 'if' will highlight next item and then return nil
    }

    if state == .cycle {
      AppState.shared.highlightNext()
      return
    }

    if state == .toggle {
      close()
      return
    }
  }

  private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
    // If we are in cycle mode, releasing modifiers triggers a selection
    if state == .cycle && allModifiersReleased(event) {
      DispatchQueue.main.async {
        AppState.shared.select()
      }
      return nil
    }

    // Otherwise if in opening mode, enter normal mode
    if state == .opening {
      state = .toggle
      return nil
    }

    return event
  }

  private func allModifiersReleased(_ event: NSEvent) -> Bool {
    guard let shortcut = KeyboardShortcuts.Name.popup.shortcut else {
      return false
    }

    return event.modifierFlags.isDisjoint(with: shortcut.modifiers)
  }
}
