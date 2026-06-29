import AppKit.NSEvent

/// Observable wrapper around the live modifier-flag state, updated via a local
/// `flagsChanged` event monitor.
@Observable
class ModifierFlags {
  /// The current device-independent modifier flags.
  var flags: NSEvent.ModifierFlags = []
  private var monitor: Any?

  /// Installs a local `flagsChanged` monitor that keeps `flags` in sync.
  init() {
    monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      return event
    }
  }

  /// Removes the event monitor.
  deinit {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}
