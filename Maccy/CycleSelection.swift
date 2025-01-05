import AppKit
import KeyboardShortcuts

/// Represents a popup action that cycles through clipboard history items.
final class CycleSelection {

  /// The event tap reference.
  private var eventTap: CFMachPort?
  /// The event tap's run loop source.
  private var runLoopSource: CFRunLoopSource?
  /// Pointer to callback context data (holding keyCode and modifiers).
  private var callbackContextPtr: UnsafeMutableRawPointer?
  /// Track whether the popup was opened via CycleSelection shortcut vs. another way.
  var isOpeningReason = false

  /// Initializes the popup cycle action and sets up the event tap for the popup shortcut.
  init?(_ shortcut: KeyboardShortcuts.Shortcut) {

    let keyCode: Int = shortcut.carbonKeyCode
    let modifiers: UInt64 = UInt64(shortcut.modifiers.rawValue)

    // Prepare a mask. We are interested in capturing events for keyDown, keyUp, flagsChanged.
    let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)

    // Create and retain the context to pass along in the event callback.
    let context = PopupCallbackContext(keyCode: keyCode, modifiers: modifiers)
    self.callbackContextPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())

    // Create the event tap. If this fails, something is wrong at the system level.
    guard let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: popupCallback,
      userInfo: callbackContextPtr
    ) else {
      NSLog("Failed to create event tap.")
      return nil
    }
    self.eventTap = eventTap

    // Wrap the tap in a run loop source and add it to the current run loop.
    self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

    // Enable the event tap.
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  /// Clean up resources to avoid leaks and ensure event taps are disabled on deinit.
  deinit {
    // Disable and invalidate the event tap if it exists.
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }

    // Remove the run loop source if it was added.
    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    }

    // Release the callback context pointer if it was created.
    if let contextPtr = callbackContextPtr {
      Unmanaged<PopupCallbackContext>.fromOpaque(contextPtr).release()
    }

    eventTap = nil
    runLoopSource = nil
    callbackContextPtr = nil
  }
}

/// Simple storage for the key code and modifiers needed by the callback.
private class PopupCallbackContext {
  let keyCode: Int
  let modifiers: UInt64

  init(keyCode: Int, modifiers: UInt64) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }
}

/// The callback function that receives low-level keyboard events.
func popupCallback(
  proxy: CGEventTapProxy,
  eventType: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  // Make sure we can get back the context we stored.
  guard let userInfo = userInfo else {
    // If there's no context, return the event unmodified.
    return Unmanaged.passRetained(event)
  }

  // Pull out the context without transferring ownership.
  let context = Unmanaged<PopupCallbackContext>.fromOpaque(userInfo).takeUnretainedValue()
  let cycleSelection = AppState.shared.popup.cycleSelection!
  let eventFlags = UInt64(event.flags.rawValue & UInt64(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue))

  switch eventType {
  case .keyDown:
    // Check for matching keyCode + modifiers
    if isKeyCode(event, matching: context.keyCode) && isModifiers(eventFlags, matching: context.modifiers) {
      // If the popup is open, cycle to the next item; otherwise, open the popup.
      if cycleSelection.isOpeningReason {
        AppState.shared.highlightNext()
        return nil
      }

      if !AppState.shared.popup.isOpen() {
        cycleSelection.isOpeningReason = true
        AppState.shared.popup.open(height: AppState.shared.popup.height)
        return nil
      }
    }

  case .flagsChanged:
    // If the popup is open and the event's modifiers no longer match our target,
    // perform a selection action and consume the event.
    if cycleSelection.isOpeningReason && !isModifiers(eventFlags, matching: context.modifiers) {
      DispatchQueue.main.async {
        AppState.shared.select(flags: NSEvent.ModifierFlags(event.flags))
      }
      return nil
    }

  default:
    break
  }

  // Return the event so other parts of the system can see it.
  return Unmanaged.passRetained(event)
}

/// Check if a `CGEvent` has the specified key code.
private func isKeyCode(_ event: CGEvent, matching keyCode: Int) -> Bool {
  return event.getIntegerValueField(.keyboardEventKeycode) == keyCode
}

/// Check if a `CGEvent` has (at least) the specified modifier flags.
private func isModifiers(_ eventFlags: UInt64, matching modifiers: UInt64) -> Bool {
  return (eventFlags & modifiers) == modifiers
}

extension NSEvent.ModifierFlags {
    init(_ eventFlags: CGEventFlags) {
        self = []
        if eventFlags.contains(.maskAlphaShift) { self.insert(.capsLock) }
        if eventFlags.contains(.maskShift) { self.insert(.shift) }
        if eventFlags.contains(.maskControl) { self.insert(.control) }
        if eventFlags.contains(.maskAlternate) { self.insert(.option) }
        if eventFlags.contains(.maskCommand) { self.insert(.command) }
        if eventFlags.contains(.maskNumericPad) { self.insert(.numericPad) }
        if eventFlags.contains(.maskHelp) { self.insert(.help) }
        if eventFlags.contains(.maskSecondaryFn) { self.insert(.function) }
    }
}
