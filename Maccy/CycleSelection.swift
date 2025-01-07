import AppKit
import KeyboardShortcuts

// MARK: - Cycle selection manager

/// Manages the popup action that cycles through clipboard history items.
final class CycleSelection {
  /// Indicates whether the popup is in "cycle" mode. Otherwise we are in "normal" mode
  var cycleMode = false
  /// Indicates whether the user started pressing the shortcut (but the mode hasn't been decided).
  var isOpening = false
  
  /// Reference to the event tap.
  private var eventTap: CFMachPort?
  /// The event tap's run loop source.
  private var runLoopSource: CFRunLoopSource?
  /// Pointer to callback context data.
  private var callbackContextPtr: UnsafeMutableRawPointer?
    
  init?(_ shortcut: KeyboardShortcuts.Shortcut) {
    // Shortcut is defined by keycode & modifiers
    let keyCode: Int = shortcut.carbonKeyCode
    let modifiers: UInt64 = UInt64(shortcut.modifiers.rawValue)
    
    // Events we want to capture
    let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)
    
    // Create a context object for passing data to the callback
    let context = CycleSelectionCallbackContext(
      keyCode: keyCode,
      modifiers: modifiers
    )
    
    // Retain and convert to an opaque pointer
    self.callbackContextPtr = UnsafeMutableRawPointer(
      Unmanaged.passRetained(context).toOpaque()
    )
    
    // Create the event tap
    guard let eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: cycleSelectionCallback,
      userInfo: callbackContextPtr
    ) else {
      NSLog("Failed to create event tap.")
      return nil
    }
    self.eventTap = eventTap
    
    // Create a run loop source for the tap and add it to the current run loop
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    self.runLoopSource = runLoopSource
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    
    // Enable the event tap
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }
  
  deinit {
    // Disable and invalidate the event tap if it exists
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    eventTap = nil
    
    // Remove the run loop source if it was added
    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    }
    runLoopSource = nil
    
    // Release the retained context
    if let contextPtr = callbackContextPtr {
      Unmanaged<CycleSelectionCallbackContext>.fromOpaque(contextPtr).release()
    }
    callbackContextPtr = nil
  }
}

// MARK: - Callback Context

/// Holds info we need inside the event callback function.
private class CycleSelectionCallbackContext {
  let keyCode: Int
  let modifiers: UInt64
  
  init(keyCode: Int, modifiers: UInt64) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }
}

// MARK: - Callback Function

/// The low-level callback for keyboard events.
private func cycleSelectionCallback(
  proxy: CGEventTapProxy,
  eventType: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

  guard let userInfo = userInfo else {
    NSLog("Error: Missing userInfo in cycleSelectionCallback")
    return Unmanaged.passRetained(event)
  }
  
  let context = Unmanaged<CycleSelectionCallbackContext>
    .fromOpaque(userInfo)
    .takeUnretainedValue()

  let popup = AppState.shared.popup
  guard let cycleSelection = popup.cycleSelection else {
    NSLog("Error: Missing cycleSelection reference in cycleSelectionCallback")
    return Unmanaged.passRetained(event)
  }
  
  let eventFlags = parseFlags(event.flags)
  
  switch eventType {
  case .keyDown:
    // Check if this is the designated shortcut (key + modifiers) or return
    if !isKeyCode(event, matching: context.keyCode) || !isModifiers(eventFlags, matching: context.modifiers) {
        return Unmanaged.passRetained(event)
    }
    
    // If popup is not open, open it
    if !popup.isOpen() {
      cycleSelection.isOpening = true
      popup.open(height: popup.height)
      return nil
    }
    
    // If the user presses again in opening mode, switch to cycle mode
    if cycleSelection.isOpening {
      cycleSelection.cycleMode = true
      cycleSelection.isOpening = false
      // Next 'if' will highlight next item and then return nil
    }
    
    // In cycle mode, just highlight the next item
    if cycleSelection.cycleMode {
      AppState.shared.highlightNext()
      return nil
    }
    
    // Otherwise, if the popup is open and we are in normal mode, close it
    if popup.isOpen() {
      popup.close()
      return nil
    }
    
  case .flagsChanged:
    // If we are in cycle mode, releasing modifiers triggers a selection
    if cycleSelection.cycleMode && !isModifiers(eventFlags, matching: context.modifiers) {
      DispatchQueue.main.async {
        AppState.shared.select(flags: NSEvent.ModifierFlags(event.flags))
      }
      return nil
    }
    
    // Otherwise if in opening mode, enter normal mode
    if cycleSelection.isOpening {
      cycleSelection.isOpening = false
      return nil
    }
    
  default:
    break
  }
  
  // Pass any unhandled events on
  return Unmanaged.passRetained(event)
}

// MARK: - Flag Parsing & Helpers

/// Mask for device-independent modifier flags.
private let deviceIndependentFlagsMask: UInt64 =
UInt64(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)

/// Extracts device-independent modifier bits from `CGEventFlags`.
private func parseFlags(_ flags: CGEventFlags) -> UInt64 {
  return UInt64(flags.rawValue) & deviceIndependentFlagsMask
}

/// Returns `true` if the event's keycode matches the specified code.
private func isKeyCode(_ event: CGEvent, matching keyCode: Int) -> Bool {
  return event.getIntegerValueField(.keyboardEventKeycode) == keyCode
}

/// Returns `true` if `eventFlags` contain at least the given `modifiers`.
private func isModifiers(_ eventFlags: UInt64, matching modifiers: UInt64) -> Bool {
  return (eventFlags & modifiers) == modifiers
}

/// Converts `CGEventFlags` to `NSEvent.ModifierFlags`.
private extension NSEvent.ModifierFlags {
  init(_ flags: CGEventFlags) {
    self = []
    if flags.contains(.maskAlphaShift)   { insert(.capsLock) }
    if flags.contains(.maskShift)        { insert(.shift) }
    if flags.contains(.maskControl)      { insert(.control) }
    if flags.contains(.maskAlternate)    { insert(.option) }
    if flags.contains(.maskCommand)      { insert(.command) }
    if flags.contains(.maskNumericPad)   { insert(.numericPad) }
    if flags.contains(.maskHelp)         { insert(.help) }
    if flags.contains(.maskSecondaryFn)  { insert(.function) }
  }
}
