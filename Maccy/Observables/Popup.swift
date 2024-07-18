import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

@Observable
class Popup {
  var menuPresented = false
  var appDelegate: AppDelegate? = nil

  var historyHeightOffset: CGFloat {
    if Defaults[.showSearch] && Defaults[.showFooter] {
      return 150
    } else if Defaults[.showSearch] {
      return 45
    } else if Defaults[.showFooter] {
      return 118
    } else {
      return 13
    }
  }

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

  func resize(height: CGFloat) {
    appDelegate?.panel.resizeContentHeight(to: height + historyHeightOffset)
    AppState.shared.needsResize = false
  }
}
