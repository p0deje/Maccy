import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

@Observable
class Popup {
  var menuPresented = false
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
