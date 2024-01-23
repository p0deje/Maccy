import AppKit

extension NSScreen {
  static var forPopup: NSScreen? {
    let desiredScreen = UserDefaults.standard.popupScreen
    if desiredScreen == 0 || desiredScreen > NSScreen.screens.count {
      return NSScreen.main
    } else {
      return NSScreen.screens[desiredScreen - 1]
    }
  }
}
