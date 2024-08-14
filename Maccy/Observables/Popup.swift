import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

@Observable
class Popup {
  static let verticalPadding: CGFloat = 5

  var headerHeight: CGFloat = 0
  var pinnedItemsHeight: CGFloat = 0
  var footerHeight: CGFloat = 0

  init() {
    KeyboardShortcuts.onKeyUp(for: .popup) {
      self.toggle()
    }
  }

  func toggle(at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.appDelegate?.panel.toggle(height: AppState.shared.height, at: popupPosition)
  }

  func open(height: CGFloat = AppState.shared.height, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  func close() {
    AppState.shared.appDelegate?.panel.close()
  }

  func resize(height: CGFloat) {
    let newHeight = height + headerHeight + pinnedItemsHeight + footerHeight + (Popup.verticalPadding * 2)
    AppState.shared.height = newHeight
    AppState.shared.appDelegate?.panel.verticallyResize(to: newHeight)
    AppState.shared.needsResize = false
  }
}
