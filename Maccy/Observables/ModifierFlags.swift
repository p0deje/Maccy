import AppKit.NSEvent
import Defaults

@Observable
class ModifierFlags {
  var flags: NSEvent.ModifierFlags = []
  private var monitor: Any?

  init() {
    monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      return event
    }
  }

  deinit {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}
