import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

@Observable
class Popup {
  var menuPresented = false {
    didSet {
      if let event = NSApp.currentEvent, event.type == .leftMouseUp {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifierFlags.contains(.option) {
          Defaults[.ignoreEvents].toggle()

          if modifierFlags.contains(.shift) {
            Defaults[.ignoreOnlyNextEvent] = Defaults[.ignoreEvents]
          }

          // TODO: Prevent menu from showing
        }
      }
    }
  }
  var isPresented = false
  var appDelegate: AppDelegate? = nil

  init() {
    KeyboardShortcuts.onKeyUp(for: .popup, action: toggle)
  }

  func toggle() {
    if isPresented {
      close()
    } else {
      open()
    }
  }

  func open() {
    if Defaults[.popupPosition] == .statusItem {
      menuPresented = true
    } else {
      appDelegate?.panel.open()
    }
    isPresented = true
  }

  func close() {
    if Defaults[.popupPosition] == .statusItem {
      menuPresented = false
    } else {
      appDelegate?.panel.close()
    }
    isPresented = false
  }
}
