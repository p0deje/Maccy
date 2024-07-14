import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

@Observable
class Popup {
  var menuPresented = false
  var appDelegate: AppDelegate? = nil

  init() {
    KeyboardShortcuts.onKeyUp(for: .popup, action: toggle)
  }

  func toggle() {
    if appDelegate?.panel.isPresented == true {
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
  }

  func close() {
    if Defaults[.popupPosition] == .statusItem {
      menuPresented = false
    } else {
      appDelegate?.panel.close()
    }
  }
}
