import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

@Observable
class Popup {
  static let verticalPadding: CGFloat = 5

  var menuPresented = false
  var appDelegate: AppDelegate? = nil

  var headerHeight: CGFloat = 0
  var pinnedItemsHeight: CGFloat = 0
  var footerHeight: CGFloat = 0

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
    let newHeight = height + headerHeight + pinnedItemsHeight + footerHeight + (Popup.verticalPadding * 2)
    appDelegate?.panel.resizeContentHeight(to: newHeight)
    AppState.shared.needsResize = false
  }
}
