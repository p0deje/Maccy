import AppKit
import KeyboardShortcuts

// MARK: - Shortcut Popup Mode

enum OpenShortcutMode {
  /// Default; shortcut will toggle the popup
  case normal
  /// Transition state when the shortcut is first pressed and we don't know whether we are in "normal" or "cycle" mode.
  case opening
  /// In this mode, every additional press of the main key will cycle to the next item in the paste history list.
  ///  Releasing the modifier keys will accept selection and close the popup
  case cycle
}

// MARK: - Shortcut manager

/// Manages the popup action that cycles through clipboard history items.
final class OpenShortcutManager {
  var mode: OpenShortcutMode = .normal

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var callbackContextPtr: UnsafeMutableRawPointer?

  init?(_ shortcut: KeyboardShortcuts.Shortcut) {
    let keyCode: Int = shortcut.carbonKeyCode
    let modifiers: UInt64 = UInt64(shortcut.modifiers.rawValue)

    // Events we want to capture
    let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)

    let context = OpenShortcutCallbackContext(
      keyCode: keyCode,
      modifiers: modifiers
    )

    self.callbackContextPtr = UnsafeMutableRawPointer(
      Unmanaged.passRetained(context).toOpaque()
    )

    guard let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: openShortcutCallback,
      userInfo: callbackContextPtr
    ) else {
      NSLog("Failed to create event tap.")
      return nil
    }
    self.eventTap = eventTap

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    self.runLoopSource = runLoopSource
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  deinit {
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    eventTap = nil

    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    }
    runLoopSource = nil

    if let contextPtr = callbackContextPtr {
      Unmanaged<OpenShortcutCallbackContext>.fromOpaque(contextPtr).release()
    }
    callbackContextPtr = nil
  }
}

// MARK: - Shortcut callback context

/// Holds info we need inside the event callback function.
private class OpenShortcutCallbackContext {
  let keyCode: Int
  let modifiers: UInt64

  init(keyCode: Int, modifiers: UInt64) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }
}

// MARK: - Shortcut callback functions

private func handleKeyDown(
  event: CGEvent,
  context: OpenShortcutCallbackContext,
  manager: OpenShortcutManager
) -> Unmanaged<CGEvent>? {

  let popup = AppState.shared.popup
  let eventFlags = parseFlags(event.flags)

  // Check if this is the designated shortcut (key + modifiers) or return
  if !isKeyCode(event, matching: context.keyCode) || !isModifiers(eventFlags, matching: context.modifiers) {
      return Unmanaged.passRetained(event)
  }

  if !popup.isOpen {
    manager.mode = .opening
    popup.open(height: popup.height)
    return nil
  }

  if manager.mode == .opening {
    manager.mode = .cycle
    // Next 'if' will highlight next item and then return nil
  }

  if manager.mode == .cycle {
    AppState.shared.highlightNext()
    return nil
  }

  if popup.isOpen {
    popup.close()
    return nil
  }

  return Unmanaged.passRetained(event)
}

private func handleFlagsChanged(
  event: CGEvent,
  context: OpenShortcutCallbackContext,
  manager: OpenShortcutManager
) -> Unmanaged<CGEvent>? {
  let eventFlags = parseFlags(event.flags)

  // If we are in cycle mode, releasing modifiers triggers a selection
  if manager.mode == .cycle && !isModifiers(eventFlags, matching: context.modifiers) {
    DispatchQueue.main.async {
      AppState.shared.select(flags: NSEvent.ModifierFlags(event.flags))
    }
    return nil
  }

  // Otherwise if in opening mode, enter normal mode
  if manager.mode == .opening {
    manager.mode = .normal
    return nil
  }

  return Unmanaged.passRetained(event)
}

/// The low-level callback for keyboard events.
private func openShortcutCallback(
  proxy: CGEventTapProxy,
  eventType: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

  guard let userInfo = userInfo else {
    NSLog("Error: Missing userInfo in cycleSelectionCallback")
    return Unmanaged.passRetained(event)
  }

  let context = Unmanaged<OpenShortcutCallbackContext>
    .fromOpaque(userInfo)
    .takeUnretainedValue()

  let popup = AppState.shared.popup
  guard let manager = popup.openShortcutManager else {
    NSLog("Error: Missing cycleSelection reference in cycleSelectionCallback")
    return Unmanaged.passRetained(event)
  }

  switch eventType {
  case .keyDown:
    return handleKeyDown(
      event: event,
      context: context,
      manager: manager
    )
  case .flagsChanged:
    return handleFlagsChanged(
      event: event,
      context: context,
      manager: manager
    )
  default:
    return Unmanaged.passRetained(event)
  }
}

// MARK: - Flag Parsing & Helpers

private func parseFlags(_ flags: CGEventFlags) -> UInt64 {
  return UInt64(flags.rawValue) & UInt64(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)
}

private func isKeyCode(_ event: CGEvent, matching keyCode: Int) -> Bool {
  return event.getIntegerValueField(.keyboardEventKeycode) == keyCode
}

private func isModifiers(_ eventFlags: UInt64, matching modifiers: UInt64) -> Bool {
  return (eventFlags & modifiers) == modifiers
}

private extension NSEvent.ModifierFlags {
  init(_ flags: CGEventFlags) {
    self = []
    if flags.contains(.maskAlphaShift) { insert(.capsLock) }
    if flags.contains(.maskShift) { insert(.shift) }
    if flags.contains(.maskControl) { insert(.control) }
    if flags.contains(.maskAlternate) { insert(.option) }
    if flags.contains(.maskCommand) { insert(.command) }
    if flags.contains(.maskNumericPad) { insert(.numericPad) }
    if flags.contains(.maskHelp) { insert(.help) }
    if flags.contains(.maskSecondaryFn) { insert(.function) }
  }
}
