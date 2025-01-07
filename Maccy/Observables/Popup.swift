import AppKit.NSRunningApplication
import Defaults
import KeyboardShortcuts
import Observation

@Observable
class Popup {
  let verticalPadding: CGFloat = 5

  var needsResize = false
  var height: CGFloat = 0
  var headerHeight: CGFloat = 0
  var pinnedItemsHeight: CGFloat = 0
  var footerHeight: CGFloat = 0
  var cycleSelection: CycleSelection?

  init() {
    if let shortcut = KeyboardShortcuts.getShortcut(for: .popup) {
      cycleSelection = CycleSelection(shortcut)
    }
  }

  func toggle(at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.appDelegate?.panel.toggle(height: height, at: popupPosition)
  }

  func isOpen() -> Bool {
      return AppState.shared.appDelegate?.panel.isPresented ?? false
  }

  func open(height: CGFloat, at popupPosition: PopupPosition = Defaults[.popupPosition]) {
    AppState.shared.appDelegate?.panel.open(height: height, at: popupPosition)
  }

  func close() {
    self.cycleSelection?.cycleMode = false  // reset
    self.cycleSelection?.isOpening = false  // reset
    AppState.shared.appDelegate?.panel.close()
  }

  func resize(height: CGFloat) {
    self.height = height + headerHeight + pinnedItemsHeight + footerHeight + (verticalPadding * 2)
    AppState.shared.appDelegate?.panel.verticallyResize(to: self.height)
    needsResize = false
  }
}
