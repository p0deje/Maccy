import AppKit.NSEvent
import Defaults

@Observable
class ModifierFlags {
  var flags: NSEvent.ModifierFlags = []

  init() {
    NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
      self.flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      return event
    }
  }
}
