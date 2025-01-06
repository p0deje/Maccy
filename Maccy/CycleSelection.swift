import AppKit
import KeyboardShortcuts

/// Represents a popup action that cycles through clipboard history items.
final class CycleSelection {
  
  /// Track whether the popup was opened in "cycle" mode or "normal" mode
  var cycleMode = false
  /// Transition state that happens between when the user starts pressing the shortcut and the app decides whether we are in "cycle" mode or "normal" mode
  var isOpening = false
  /// Task that decides whether to enter cycle mode or normal mode
  private var task: DispatchWorkItem?
  /// The event tap reference.
  private var eventTap: CFMachPort?
  /// The event tap's run loop source.
  private var runLoopSource: CFRunLoopSource?
  /// Pointer to callback context data (holding keyCode and modifiers).
  private var callbackContextPtr: UnsafeMutableRawPointer?
  
  /// Initializes the popup cycle action and sets up the event tap for the popup shortcut.
  init?(_ shortcut: KeyboardShortcuts.Shortcut) {
    
    // Shortcut is defined by keycode & modifierts
    let keyCode: Int = shortcut.carbonKeyCode
    let modifiers: UInt64 = UInt64(shortcut.modifiers.rawValue)
    
    // Events that we want to capture
    let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)
    
    // Create and retain the context to pass along in the event callback.
    let context = CycleSelectionCallbackContext(keyCode: keyCode, modifiers: modifiers, task: task)
    self.callbackContextPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())
    
    // Create the event tap. If this fails, something is wrong at the system level.
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
    
    // Wrap the tap in a run loop source and add it to the current run loop.
    self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    
    // Enable the event tap.
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }
  
  /// Clean up resources to avoid leaks and ensure event taps are disabled on deinit.
  deinit {
    
    // Cancel and delete the task if created
    task?.cancel()
    task = nil
    
    // Disable and invalidate the event tap if it exists.
    if let eventTap = eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    eventTap = nil
    
    // Remove the run loop source if it was added.
    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    }
    runLoopSource = nil
    
    // Release the callback context pointer if it was created.
    if let contextPtr = callbackContextPtr {
      Unmanaged<CycleSelectionCallbackContext>.fromOpaque(contextPtr).release()
    }
    callbackContextPtr = nil
  }
}

/// Object that can be passed to the callback with necessary information
private class CycleSelectionCallbackContext {
  let keyCode: Int
  let modifiers: UInt64
  var task: DispatchWorkItem?
  
  init(keyCode: Int, modifiers: UInt64, task: DispatchWorkItem?) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.task = task
  }
}

/// The callback function that receives low-level keyboard events.
private func cycleSelectionCallback(
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
  let context = Unmanaged<CycleSelectionCallbackContext>.fromOpaque(userInfo).takeUnretainedValue()
  let cycleSelection = AppState.shared.popup.cycleSelection!
  let eventFlags = parseFlags(event.flags)
  
  switch eventType {
  case .keyDown:
    // Check for matching keyCode + modifiers
    if isKeyCode(event, matching: context.keyCode) && isModifiers(eventFlags, matching: context.modifiers) {
      
      if !AppState.shared.popup.isOpen() {
        cycleSelection.isOpening = true
        AppState.shared.popup.open(height: AppState.shared.popup.height)
        return nil
      }
      
      // If C is kept pressed, consider that the user wants to enter cycle mode
      if cycleSelection.isOpening {
        context.task?.cancel()
        cycleSelection.cycleMode = true
        cycleSelection.isOpening = false
        // next if will return nil after highlighting next item
      }
      
      if cycleSelection.cycleMode {
        AppState.shared.highlightNext()
        return nil
      }
      
      if AppState.shared.popup.isOpen() {
        AppState.shared.popup.close()
        return nil
      }
    }
    
  case .keyUp:
    if isKeyCode(event, matching: context.keyCode) && cycleSelection.isOpening {
      // We create a task to dispatch an event after a delta. This is in case the main key is released closely but not exactly at
      // the same time as the modifiers. Within the delta timeframe, we will assume that they were released together.
      context.task?.cancel()
      let task = DispatchWorkItem {
        let flagsNewValue = parseFlags(CGEventSource.flagsState(.combinedSessionState))
        cycleSelection.isOpening = false
        if isModifiers(flagsNewValue, matching: context.modifiers) {
          cycleSelection.cycleMode = true  // Keep Maccy open and put in Cycle mode
        }  // else do nothing, just keep Maccy Open in "normal" mode
        
      }
      context.task = task
      let delta = 0.2  // seconds
      DispatchQueue.main.asyncAfter(deadline: .now() + delta, execute: task)
      
      return nil
    }
    
  case .flagsChanged:
    // If the popup is open in cycle mode and the event's modifiers are released,
    // perform a selection action and consume the event.
    if cycleSelection.cycleMode && !isModifiers(eventFlags, matching: context.modifiers) {
      DispatchQueue.main.async {
        AppState.shared.select(flags: NSEvent.ModifierFlags(event.flags))
      }
      return nil
    }
    
  default:
    break
  }
  
  // Cases we don't handle. Default to returning the event so that other parts of the system can see or use it.
  return Unmanaged.passRetained(event)
}

/// Helper function to parse the raw value of the modifier flags. Device dependent bits are filtered out
private func parseFlags(_ flags: CGEventFlags) -> UInt64 {
  return UInt64(flags.rawValue) & UInt64(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)
}

/// Check if a `CGEvent` has the specified key code.
private func isKeyCode(_ event: CGEvent, matching keyCode: Int) -> Bool {
  return event.getIntegerValueField(.keyboardEventKeycode) == keyCode
}

/// Check if a `CGEvent` has (at least) the specified modifier flags.
private func isModifiers(_ eventFlags: UInt64, matching modifiers: UInt64) -> Bool {
  return (eventFlags & modifiers) == modifiers
}

/// Extension to convert CGEventFlags to NSEvent.ModifierFlags
private extension NSEvent.ModifierFlags {
  init(_ flags: CGEventFlags) {
    self = []
    if flags.contains(.maskAlphaShift) { self.insert(.capsLock) }
    if flags.contains(.maskShift) { self.insert(.shift) }
    if flags.contains(.maskControl) { self.insert(.control) }
    if flags.contains(.maskAlternate) { self.insert(.option) }
    if flags.contains(.maskCommand) { self.insert(.command) }
    if flags.contains(.maskNumericPad) { self.insert(.numericPad) }
    if flags.contains(.maskHelp) { self.insert(.help) }
    if flags.contains(.maskSecondaryFn) { self.insert(.function) }
  }
}
